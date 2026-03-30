import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/ticket_updates_service.dart';
import '../../services/vps_sync_service.dart';
import '../../services/whatsapp_conversation_service.dart';
import '../../pages/whatsapp_conversations_page.dart' as conv_page;
import '../../widgets/window_close_handler_fixed.dart';
import '../tickets/tktats_page.dart';
import '../whatsapp/whatsapp_bottom_window.dart';
import 'agent_tasks_bubble.dart';

/// شريط أدوات عائم موحد — يجمع كل الأزرار العائمة في بطاقة واحدة قابلة للسحب.
class FloatingToolbar {
  FloatingToolbar._();

  static OverlayEntry? _entry;
  static bool _isShowing = false;
  static OverlayState? _rootOverlay;

  // حالة الأزرار
  static bool _showWhatsApp = false;
  static bool _showConversations = false;
  static bool _showVpsSync = false;
  static bool _isAdmin = false;

  // notifiers
  static final ValueNotifier<int> _taskCount = ValueNotifier<int>(0);
  static final ValueNotifier<bool> _shakeNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<_ToolbarConfig> _configNotifier =
      ValueNotifier<_ToolbarConfig>(_ToolbarConfig());

  static StreamSubscription? _taskCountSub;
  static StreamSubscription? _newTicketsSub;

  /// تهيئة الشريط العائم — يُستدعى من home_page
  static void init(BuildContext context) {
    try {
      _rootOverlay = Overlay.of(context, rootOverlay: true);
    } catch (e) {
      debugPrint('[FloatingToolbar] init overlay failed');
      return;
    }

    // منع إنشاء أزرار FAB فردية قديمة وإزالة الموجودة
    WhatsAppBottomWindow.suppressIndividualFabs = true;
    WhatsAppBottomWindow.removeAllFabs();
    AgentTasksBubble.suppressIndividualBubble = true;

    // الاشتراك في عدد تاسكات الوكيل
    _taskCountSub?.cancel();
    _taskCountSub =
        TicketUpdatesService.instance.agentTaskCountStream.listen((count) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _taskCount.value = count;
        _refreshConfig();
      });
    });

    _newTicketsSub?.cancel();
    _newTicketsSub =
        TicketUpdatesService.instance.newTicketsStream.listen((newTasks) {
      if (newTasks.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _shakeNotifier.value = true;
        });
        Future.delayed(const Duration(milliseconds: 800), () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _shakeNotifier.value = false;
          });
        });
      }
    });

    // عدد حالي
    final current = TicketUpdatesService.instance.lastAgentCount;
    if (current > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _taskCount.value = current;
        _refreshConfig();
      });
    }
  }

  /// إظهار زر واتساب ويب
  static void enableWhatsApp() {
    _showWhatsApp = true;
    _scheduleRefresh();
  }

  /// إظهار زر محادثات الواتساب
  static void enableConversations({bool isAdmin = false}) {
    _showConversations = true;
    _isAdmin = isAdmin;
    _scheduleRefresh();
  }

  /// إخفاء زر المحادثات
  static void disableConversations() {
    _showConversations = false;
    _scheduleRefresh();
  }

  /// إظهار زر تحديث VPS
  static void enableVpsSync() {
    _showVpsSync = true;
    _scheduleRefresh();
  }

  /// جدولة تحديث آمن — دائماً يؤجَّل لما بعد الـ frame الحالي
  static bool _refreshScheduled = false;
  static void _scheduleRefresh() {
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      _refreshConfig();
    });
  }

  static void _refreshConfig() {
    final hasAny =
        _showWhatsApp || _showConversations || _showVpsSync || _taskCount.value > 0;
    _configNotifier.value = _ToolbarConfig(
      showWhatsApp: _showWhatsApp,
      showConversations: _showConversations,
      showVpsSync: _showVpsSync,
      taskCount: _taskCount.value,
    );
    if (hasAny && !_isShowing) {
      _show();
    } else if (!hasAny && _isShowing) {
      _hide();
    }
    _entry?.markNeedsBuild();
  }

  static void _show() {
    if (_isShowing || _rootOverlay == null) return;
    _entry = OverlayEntry(builder: (_) => _ToolbarOverlay(
      configNotifier: _configNotifier,
      taskCountNotifier: _taskCount,
      shakeNotifier: _shakeNotifier,
      isAdmin: _isAdmin,
    ));
    _rootOverlay!.insert(_entry!);
    _isShowing = true;
  }

  static void _hide() {
    _entry?.remove();
    _entry = null;
    _isShowing = false;
  }

  static void dispose() {
    _taskCountSub?.cancel();
    _newTicketsSub?.cancel();
    _hide(); // إزالة الـ overlay أولاً حتى لا يكون هناك listener
    _rootOverlay = null;
    _showWhatsApp = false;
    _showConversations = false;
    _showVpsSync = false;
    _refreshScheduled = false;
    // تأجيل تصفير القيم لتجنب خطأ widget tree locked
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _taskCount.value = 0;
    });
    // إعادة تفعيل الأزرار الفردية عند التخلص
    WhatsAppBottomWindow.suppressIndividualFabs = false;
    AgentTasksBubble.suppressIndividualBubble = false;
  }
}

class _ToolbarConfig {
  final bool showWhatsApp;
  final bool showConversations;
  final bool showVpsSync;
  final int taskCount;
  _ToolbarConfig({
    this.showWhatsApp = false,
    this.showConversations = false,
    this.showVpsSync = false,
    this.taskCount = 0,
  });
}

/// الويدجت العائم القابل للسحب
class _ToolbarOverlay extends StatefulWidget {
  final ValueNotifier<_ToolbarConfig> configNotifier;
  final ValueNotifier<int> taskCountNotifier;
  final ValueNotifier<bool> shakeNotifier;
  final bool isAdmin;

  const _ToolbarOverlay({
    required this.configNotifier,
    required this.taskCountNotifier,
    required this.shakeNotifier,
    required this.isAdmin,
  });

  @override
  State<_ToolbarOverlay> createState() => _ToolbarOverlayState();
}

class _ToolbarOverlayState extends State<_ToolbarOverlay>
    with SingleTickerProviderStateMixin {
  // موضع البطاقة (يبدأ من الوسط السفلي)
  double? _dx;
  double? _dy;

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

    widget.shakeNotifier.addListener(_onShake);
  }

  void _onShake() {
    if (widget.shakeNotifier.value) {
      _shakeCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    widget.shakeNotifier.removeListener(_onShake);
    _shakeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context).size;

    return ValueListenableBuilder<_ToolbarConfig>(
      valueListenable: widget.configNotifier,
      builder: (_, config, __) {
        final buttons = <Widget>[];

        // زر محادثات الواتساب
        if (config.showConversations) {
          buttons.add(_buildConversationsBtn(context, mq));
        }

        // زر تاسكات الوكيل — دائماً موجود، يختفي ذاتياً إذا العدد = 0
        buttons.add(ValueListenableBuilder<int>(
          valueListenable: widget.taskCountNotifier,
          builder: (_, count, __) {
            if (count <= 0) return const SizedBox.shrink();
            return AnimatedBuilder(
              animation: _shakeAnim,
              builder: (_, child) =>
                  Transform.rotate(angle: _shakeAnim.value, child: child),
              child: _buildTasksBtn(context, count),
            );
          },
        ));

        // زر واتساب ويب
        if (config.showWhatsApp) {
          buttons.add(_buildWhatsAppBtn(context));
        }

        // زر تحديث VPS
        if (config.showVpsSync) {
          buttons.add(_buildVpsSyncBtn(context));
        }

        if (buttons.isEmpty) return const SizedBox.shrink();

        // الموضع الافتراضي: يسار الأسفل (مع مراعاة BottomNav على الموبايل)
        final isMobile = Platform.isAndroid || Platform.isIOS;
        final dx = _dx ?? 16.0;
        final dy = _dy ?? (mq.height - (isMobile ? 140 : 70));

        return Positioned(
          left: dx,
          top: dy,
          child: GestureDetector(
            onPanUpdate: (d) {
              setState(() {
                _dx = (_dx ?? dx) + d.delta.dx;
                _dy = (_dy ?? dy) + d.delta.dy;
                // حدود الشاشة (مع مراعاة BottomNav على الموبايل)
                _dx = _dx!.clamp(0.0, mq.width - 200);
                _dy = _dy!.clamp(40.0, mq.height - (isMobile ? 120 : 60));
              });
            },
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(24),
              color: Colors.white.withValues(alpha: 0.95),
              shadowColor: Colors.black38,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade300, width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // مقبض السحب
                    Icon(Icons.drag_indicator,
                        size: 18, color: Colors.grey.shade400),
                    const SizedBox(width: 2),
                    ...buttons,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWhatsAppBtn(BuildContext context) {
    return Tooltip(
      message: 'واتساب عادي',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Material(
            color: const Color(0xFF25D366),
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                WhatsAppBottomWindow.showBottomWindow(context, '', '');
              },
              child: const Center(
                child: Icon(Icons.chat, color: Colors.white, size: 18),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConversationsBtn(BuildContext context, Size mq) {
    return Tooltip(
      message: 'واتساب خاص',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: StreamBuilder<int>(
          stream: WhatsAppConversationService.getUnreadCount(),
          builder: (context, snapshot) {
            final unread = snapshot.data ?? 0;
            return SizedBox(
              width: 38,
              height: 38,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Material(
                    color: const Color(0xFF128C7E),
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        if (conv_page.WhatsAppConversationsPage.isOpen) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => conv_page.WhatsAppConversationsPage(
                                isAdmin: widget.isAdmin),
                          ),
                        );
                      },
                      child: const Center(
                        child: Icon(Icons.chat_bubble,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                if (unread > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
        ),
      ),
    );
  }

  Widget _buildTasksBtn(BuildContext context, int count) {
    return Tooltip(
      message: 'تكتات مفتوحة ($count)',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: SizedBox(
        width: 38,
        height: 38,
        child: Material(
          color: Colors.orange.shade700,
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              final ctx = navigatorKey.currentContext;
              if (ctx == null) return;
              final token = TicketUpdatesService.instance.currentToken;
              if (token == null || token.isEmpty) return;
              Navigator.of(ctx).push(
                PageRouteBuilder(
                  pageBuilder: (c, a, b) => TKTATsPage(authToken: token, initialTab: 'open'),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                  transitionsBuilder: (c, a, b, child) => child,
                ),
              );
            },
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.assignment_late,
                      color: Colors.white, size: 14),
                  Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
       ),
      ),
    );
  }

  Widget _buildVpsSyncBtn(BuildContext context) {
    final vps = VpsSyncService.instance;
    return AnimatedBuilder(
      animation: vps,
      builder: (_, __) {
        final syncing = vps.isSyncing;
        return Tooltip(
          message: syncing ? vps.statusMessage : 'تحديث البيانات من السيرفر',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: SizedBox(
              width: 38,
              height: 38,
              child: Material(
                color: syncing ? Colors.blue.shade600 : Colors.indigo.shade600,
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: syncing
                      ? null
                      : () async {
                          final result = await vps.syncFromVps();
                          if (context.mounted) {
                            final msg = result.success
                                ? 'تم التحديث — ${result.totalCount} مشترك'
                                : result.error ?? 'فشل التحديث';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(msg),
                                duration: const Duration(seconds: 3),
                                backgroundColor:
                                    result.success ? Colors.green : Colors.red,
                              ),
                            );
                          }
                        },
                  child: Center(
                    child: syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.cloud_download,
                            color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
