import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/ticket_updates_service.dart';
import '../../widgets/window_close_handler_fixed.dart';
import '../tickets/tktats_page.dart';

/// فقاعة عائمة تعرض عدد تاسكات الوكيل المفتوحة على أي شاشة.
/// تتبع نفس نمط WhatsAppBottomWindow (static OverlayEntry + rootOverlay).
class AgentTasksBubble {
  AgentTasksBubble._();

  /// عند true، لا تُنشأ فقاعة فردية (FloatingToolbar يتولى المهمة)
  static bool suppressIndividualBubble = false;

  static OverlayEntry? _bubbleEntry;
  static bool _isShowing = false;
  static OverlayState? _rootOverlay;
  static bool _initialized = false;

  static final ValueNotifier<int> _countNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<bool> _shakeNotifier = ValueNotifier<bool>(false);

  static StreamSubscription? _countSub;
  static StreamSubscription? _newTicketsSub;

  /// يُستدعى من home_page بعد تسجيل الدخول
  static void init(BuildContext context) {
    if (_initialized) return;
    try {
      _rootOverlay = Overlay.of(context, rootOverlay: true);
      _initialized = _rootOverlay != null;
    } catch (e) {
      debugPrint('[AgentTasksBubble] init failed: $e');
      return;
    }

    // الاشتراك في عدد تاسكات الوكيل
    _countSub = TicketUpdatesService.instance.agentTaskCountStream.listen((count) {
      _countNotifier.value = count;
      if (count > 0 && !_isShowing) {
        _show();
      } else if (count == 0 && _isShowing) {
        _hide();
      }
    });

    // الاشتراك في التاسكات الجديدة (للاهتزاز)
    _newTicketsSub = TicketUpdatesService.instance.newTicketsStream.listen((newTasks) {
      if (newTasks.isNotEmpty) {
        _triggerShake();
      }
    });

    // عرض فوري إذا كان هناك تاسكات بالفعل
    final current = TicketUpdatesService.instance.lastAgentCount;
    if (current > 0) {
      _countNotifier.value = current;
      _show();
    }
  }

  static void _show() {
    if (suppressIndividualBubble) return; // FloatingToolbar يتولى المهمة
    if (_isShowing || _rootOverlay == null) return;
    _bubbleEntry = OverlayEntry(
      builder: (_) => _BubbleOverlay(
        countNotifier: _countNotifier,
        shakeNotifier: _shakeNotifier,
        onTap: _navigateToTasksPage,
      ),
    );
    _rootOverlay!.insert(_bubbleEntry!);
    _isShowing = true;
  }

  static void _hide() {
    _bubbleEntry?.remove();
    _bubbleEntry = null;
    _isShowing = false;
  }

  static void _triggerShake() {
    _shakeNotifier.value = true;
    Future.delayed(const Duration(milliseconds: 800), () {
      _shakeNotifier.value = false;
    });
  }

  static void _navigateToTasksPage() {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    final token = TicketUpdatesService.instance.currentToken;
    if (token == null || token.isEmpty) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (ctx, a, b) => TKTATsPage(authToken: token),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (ctx, a, b, child) => child,
      ),
    );
  }

  static void dispose() {
    _countSub?.cancel();
    _newTicketsSub?.cancel();
    _hide();
    _initialized = false;
    _rootOverlay = null;
  }
}

/// الويدجت الذي يُعرض كـ OverlayEntry
class _BubbleOverlay extends StatelessWidget {
  final ValueNotifier<int> countNotifier;
  final ValueNotifier<bool> shakeNotifier;
  final VoidCallback onTap;

  const _BubbleOverlay({
    required this.countNotifier,
    required this.shakeNotifier,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: countNotifier,
      builder: (_, count, __) {
        if (count <= 0) return const SizedBox.shrink();
        return Positioned(
          bottom: 150,
          left: 20,
          child: ValueListenableBuilder<bool>(
            valueListenable: shakeNotifier,
            builder: (_, shaking, __) {
              return _AgentBubbleWidget(
                count: count,
                isShaking: shaking,
                onTap: onTap,
              );
            },
          ),
        );
      },
    );
  }
}

/// دائرة الفقاعة مع حركة الاهتزاز
class _AgentBubbleWidget extends StatefulWidget {
  final int count;
  final bool isShaking;
  final VoidCallback onTap;

  const _AgentBubbleWidget({
    required this.count,
    required this.isShaking,
    required this.onTap,
  });

  @override
  State<_AgentBubbleWidget> createState() => _AgentBubbleWidgetState();
}

class _AgentBubbleWidgetState extends State<_AgentBubbleWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.12, end: -0.12), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.12, end: 0.08), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.08, end: -0.04), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.04, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant _AgentBubbleWidget old) {
    super.didUpdateWidget(old);
    if (widget.isShaking && !old.isShaking) {
      _shakeCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (_, child) => Transform.rotate(angle: _shakeAnim.value, child: child),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.orange.shade600, Colors.deepOrange.shade700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.deepOrange.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.assignment_late, color: Colors.white, size: 18),
                Text(
                  '${widget.count}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
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
