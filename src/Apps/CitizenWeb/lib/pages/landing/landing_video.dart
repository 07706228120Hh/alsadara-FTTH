import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'landing_data.dart';
import 'landing_effects.dart';
import 'landing_style.dart';

// ═══════════════════════════════════════════════════════════════
// HeroPlayer: يشغّل فيديو كل خدمة بالتسلسل (بدون صوت، تلقائياً)
// ═══════════════════════════════════════════════════════════════
class HeroPlayerController extends ChangeNotifier {
  int index = 0;
  void select(int i) {
    index = i;
    notifyListeners();
  }
}

class HeroPlayer extends StatefulWidget {
  final HeroPlayerController controller;
  final ValueChanged<int> onIndexChanged;
  const HeroPlayer({super.key, required this.controller, required this.onIndexChanged});

  @override
  State<HeroPlayer> createState() => _HeroPlayerState();
}

class _HeroPlayerState extends State<HeroPlayer> {
  VideoPlayerController? _vc;
  int _index = 0;
  bool _userPaused = false;
  bool _blocked = false; // المتصفح رفض التشغيل التلقائي
  bool _muted = true;
  bool _failed = false;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onExternalSelect);
    _load(0, initial: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) _userPaused = true;
  }

  void _onExternalSelect() {
    final i = widget.controller.index;
    _userPaused = false;
    _load(i);
  }

  Future<void> _load(int i, {bool initial = false}) async {
    final old = _vc;
    old?.removeListener(_tick);
    void reset() {
      _index = i;
      _failed = false;
      _vc = null;
    }

    if (initial) {
      reset();
    } else {
      setState(reset);
    }
    // نُبلغ الصفحة بعد انتهاء الإطار الحالي حتى لا نعيد بناءها أثناء البناء
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onIndexChanged(i);
    });
    final vc = VideoPlayerController.asset(kServices[i].video, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    try {
      await vc.initialize();
      await vc.setVolume(_muted ? 0 : 1);
      await vc.setLooping(false);
    } catch (_) {
      if (mounted && _index == i) setState(() => _failed = true);
      await vc.dispose();
      return;
    }
    await old?.dispose();
    if (!mounted || _index != i) {
      await vc.dispose();
      return;
    }
    vc.addListener(_tick);
    setState(() => _vc = vc);
    _tryPlay();
  }

  Future<void> _tryPlay() async {
    final vc = _vc;
    if (vc == null || _userPaused || !_visible) return;
    try {
      await vc.play();
      if (mounted) setState(() => _blocked = false);
    } catch (_) {
      if (mounted) setState(() => _blocked = true);
    }
  }

  void _tick() {
    final vc = _vc;
    if (vc == null) return;
    final v = vc.value;
    if (v.hasError && !_failed) setState(() => _failed = true);
    // انتهى الفيديو ← الخدمة التالية
    if (v.isInitialized && v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 120) && !v.isPlaying) {
      vc.removeListener(_tick);
      _load((_index + 1) % kServices.length);
      return;
    }
    // المتصفح أوقف التشغيل التلقائي: نجرّب عند أول تفاعل
    if (mounted) setState(() {});
  }

  void _toggle() {
    final vc = _vc;
    if (vc == null) return;
    if (vc.value.isPlaying) {
      _userPaused = true;
      vc.pause();
    } else {
      _userPaused = false;
      _blocked = false;
      vc.play();
    }
    setState(() {});
  }

  void _toggleMute() {
    _muted = !_muted;
    _vc?.setVolume(_muted ? 0 : 1);
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExternalSelect);
    _vc?.removeListener(_tick);
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vc = _vc;
    final ready = vc != null && vc.value.isInitialized;
    final playing = ready && vc.value.isPlaying;
    final progress = ready && vc.value.duration.inMilliseconds > 0 ? (vc.value.position.inMilliseconds / vc.value.duration.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    final s = kServices[_index];

    return VisibilityDetector(
      key: const Key('hero-player'),
      onVisibilityChanged: (info) {
        _visible = info.visibleFraction > .2;
        if (!_visible) {
          _vc?.pause();
        } else {
          _tryPlay();
        }
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // الإطار
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: LColors.goldLight.withValues(alpha: .45)),
              color: const Color(0xFFF4F7FC),
              boxShadow: const [
                BoxShadow(color: Color(0xFF071430), offset: Offset(0, 10)),
                BoxShadow(color: Color(0xB3000000), offset: Offset(0, 40), blurRadius: 90, spreadRadius: -40),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(31),
              child: GestureDetector(
                onTap: _toggle,
                child: Stack(fit: StackFit.expand, children: [
                  Image.asset(s.poster, fit: BoxFit.cover, gaplessPlayback: true),
                  if (ready)
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(width: vc.value.size.width, height: vc.value.size.height, child: VideoPlayer(vc)),
                    ),
                  if (_failed)
                    Container(color: const Color(0xE6F4F7FC), alignment: Alignment.center, child: Text('تعذّر تشغيل الفيديو', style: LText.b(15))),
                  if (ready && !playing && (_userPaused || _blocked))
                    Center(
                      child: Semantics(
                        button: true,
                        label: 'تشغيل الفيديو',
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: LColors.teal,
                            boxShadow: [BoxShadow(color: LColors.edgeTeal, offset: Offset(0, 6)), BoxShadow(color: Color(0xCC0E7490), offset: Offset(0, 20), blurRadius: 40, spreadRadius: -14)],
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 44),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // شريط التحكم: إيقاف/تشغيل + أجزاء التقدم + الصوت
        Row(children: [
          _CtlButton(icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded, label: playing ? 'إيقاف الفيديو مؤقتاً' : 'تشغيل الفيديو', onTap: _toggle),
          const SizedBox(width: 10),
          Expanded(
            child: Row(children: [
              for (int j = 0; j < kServices.length; j++) ...[
                if (j > 0) const SizedBox(width: 6),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: kServices[j].title,
                    selected: j == _index,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _userPaused = false;
                        _load(j);
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: SizedBox(
                          height: 30,
                          child: Center(
                            child: Stack(children: [
                              Container(height: 6, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(9))),
                              FractionallySizedBox(
                                alignment: AlignmentDirectional.centerStart,
                                widthFactor: j < _index ? 1 : (j == _index ? progress : 0),
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [LColors.goldLight, LColors.goldPale]),
                                    borderRadius: BorderRadius.circular(9),
                                    boxShadow: [BoxShadow(color: LColors.goldLight.withValues(alpha: .7), blurRadius: 12)],
                                  ),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(width: 10),
          _CtlButton(icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, label: _muted ? 'تشغيل الصوت' : 'كتم الصوت', onTap: _toggleMute),
        ]),
      ]),
    );
  }
}

class _CtlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _CtlButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: .2)),
              boxShadow: const [BoxShadow(color: Color(0x59000000), offset: Offset(0, 4))],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// MiniVideo: فيديو الخدمة داخل بطاقتها — يعمل فقط وهو ظاهر على الشاشة
// ═══════════════════════════════════════════════════════════════
class MiniVideo extends StatefulWidget {
  final LService service;
  const MiniVideo({super.key, required this.service});
  @override
  State<MiniVideo> createState() => _MiniVideoState();
}

class _MiniVideoState extends State<MiniVideo> {
  VideoPlayerController? _vc;
  bool _loading = false;

  Future<void> _ensure() async {
    if (_vc != null || _loading) return;
    _loading = true;
    final vc = VideoPlayerController.asset(widget.service.video, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    try {
      await vc.initialize();
      await vc.setVolume(0);
      await vc.setLooping(true);
      if (!mounted) {
        await vc.dispose();
        return;
      }
      setState(() => _vc = vc);
      vc.play().catchError((_) {});
    } catch (_) {
      await vc.dispose();
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vc = _vc;
    return VisibilityDetector(
      key: Key('mini-${widget.service.key}'),
      onVisibilityChanged: (info) {
        if (reduceMotion(context)) return;
        if (info.visibleFraction > .25) {
          if (_vc == null) {
            _ensure();
          } else {
            _vc!.play().catchError((_) {});
          }
        } else {
          _vc?.pause();
        }
      },
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Color(0x99132A5E), offset: Offset(0, 14), blurRadius: 26, spreadRadius: -18)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(fit: StackFit.expand, children: [
              Image.asset(widget.service.poster, fit: BoxFit.cover),
              if (vc != null && vc.value.isInitialized)
                FittedBox(fit: BoxFit.cover, child: SizedBox(width: vc.value.size.width, height: vc.value.size.height, child: VideoPlayer(vc))),
            ]),
          ),
        ),
      ),
    );
  }
}
