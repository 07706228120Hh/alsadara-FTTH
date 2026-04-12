import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/chat_service.dart';
import '../../services/notification_api_service.dart';
import '../../services/ticket_updates_service.dart';
import '../../services/vps_sync_service.dart';
import '../../services/whatsapp_conversation_service.dart';
import '../../pages/whatsapp_conversations_page.dart' as conv_page;
import '../../pages/chat/chat_rooms_page.dart';
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
  static bool _showTasks = false;       // تذاكر FTTH
  static bool _showS1Tasks = false;     // مهام النظام الأول
  static bool _showChat = false;
  static bool _showNotifications = false;
  static bool _isAdmin = false;

  // callback للمهام (النظام الأول)
  static VoidCallback? _s1TasksOnTap;
  static int _s1TasksCount = 0;

  // notifiers
  static final ValueNotifier<int> _taskCount = ValueNotifier<int>(0);
  static final ValueNotifier<bool> _shakeNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<int> _chatUnreadCount = ValueNotifier<int>(0);
  static final ValueNotifier<int> _notifUnreadCount = ValueNotifier<int>(0);
  static final ValueNotifier<_ToolbarConfig> _configNotifier =
      ValueNotifier<_ToolbarConfig>(_ToolbarConfig());

  static StreamSubscription? _taskCountSub;
  static StreamSubscription? _newTicketsSub;
  static StreamSubscription? _chatUnreadSub;
  static Timer? _notifTimer;

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

  /// إظهار زر التذاكر (FTTH) في الشريط العائم
  static void enableTasks() {
    _showTasks = true;
    _scheduleRefresh();
  }

  /// إخفاء زر التذاكر
  static void disableTasks() {
    _showTasks = false;
    _scheduleRefresh();
  }

  /// إظهار زر المهام (النظام الأول) في الشريط العائم
  static void enableS1Tasks({required VoidCallback onTap, int badgeCount = 0}) {
    _showS1Tasks = true;
    _s1TasksOnTap = onTap;
    _s1TasksCount = badgeCount;
    _scheduleRefresh();
  }

  /// تحديث بادج المهام
  static void updateS1TasksBadge(int count) {
    _s1TasksCount = count;
    _scheduleRefresh();
  }

  /// إعادة تفعيل زر المهام (النظام الأول) إذا كان مُفعّلاً سابقاً
  static void reEnableS1Tasks() {
    if (_s1TasksOnTap != null) {
      _showS1Tasks = true;
      _scheduleRefresh();
    }
  }

  /// إخفاء زر المهام (النظام الأول)
  static void disableS1Tasks() {
    _showS1Tasks = false;
    _s1TasksOnTap = null;
    _s1TasksCount = 0;
    _scheduleRefresh();
  }

  /// إظهار زر المحادثة الداخلية في الشريط العائم
  static void enableChat() {
    _showChat = true;
    // الاشتراك في عداد الرسائل غير المقروءة
    _chatUnreadSub?.cancel();
    _chatUnreadSub = ChatService.instance.onUnreadCount.listen((count) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chatUnreadCount.value = count;
      });
    });
    ChatService.instance.refreshUnreadCount();
    _scheduleRefresh();
  }

  /// إخفاء زر المحادثة الداخلية
  static void disableChat() {
    _showChat = false;
    _chatUnreadSub?.cancel();
    _chatUnreadSub = null;
    _scheduleRefresh();
  }

  /// إظهار زر الإشعارات في الشريط العائم
  static void enableNotifications() {
    _showNotifications = true;
    // جلب عدد الإشعارات غير المقروءة كل 30 ثانية
    _notifTimer?.cancel();
    _fetchNotifCount();
    _notifTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchNotifCount();
    });
    _scheduleRefresh();
  }

  /// إخفاء زر الإشعارات
  static void disableNotifications() {
    _showNotifications = false;
    _notifTimer?.cancel();
    _notifTimer = null;
    _scheduleRefresh();
  }

  static Future<void> _fetchNotifCount() async {
    try {
      final res = await NotificationApiService.instance.getUnreadCount();
      if (res['success'] == true) {
        final count = (res['data'] ?? 0) as int;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _notifUnreadCount.value = count;
        });
      }
    } catch (_) {}
  }

  /// تحديث عداد الإشعارات يدوياً (يُستدعى بعد قراءة إشعار)
  static void refreshNotifCount() => _fetchNotifCount();

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
    final hasAny = _showWhatsApp ||
        _showConversations ||
        _showVpsSync ||
        _showTasks ||
        _showS1Tasks ||
        _showChat ||
        _showNotifications ||
        _taskCount.value > 0;
    _configNotifier.value = _ToolbarConfig(
      showWhatsApp: _showWhatsApp,
      showConversations: _showConversations,
      showVpsSync: _showVpsSync,
      showTasks: _showTasks,
      showS1Tasks: _showS1Tasks,
      showChat: _showChat,
      showNotifications: _showNotifications,
      taskCount: _taskCount.value,
      s1TasksCount: _s1TasksCount,
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
      chatUnreadNotifier: _chatUnreadCount,
      notifUnreadNotifier: _notifUnreadCount,
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
    _chatUnreadSub?.cancel();
    _notifTimer?.cancel();
    _notifTimer = null;
    _chatUnreadSub = null;
    _hide();
    _rootOverlay = null;
    _showWhatsApp = false;
    _showConversations = false;
    _showVpsSync = false;
    _showTasks = false;
    _showS1Tasks = false;
    _s1TasksOnTap = null;
    _s1TasksCount = 0;
    _showChat = false;
    _showNotifications = false;
    _refreshScheduled = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _taskCount.value = 0;
      _chatUnreadCount.value = 0;
      _notifUnreadCount.value = 0;
    });
    WhatsAppBottomWindow.suppressIndividualFabs = false;
    AgentTasksBubble.suppressIndividualBubble = false;
  }
}

class _ToolbarConfig {
  final bool showWhatsApp;
  final bool showConversations;
  final bool showVpsSync;
  final bool showTasks;
  final bool showS1Tasks;
  final bool showChat;
  final bool showNotifications;
  final int taskCount;
  final int s1TasksCount;
  _ToolbarConfig({
    this.showWhatsApp = false,
    this.showConversations = false,
    this.showVpsSync = false,
    this.showTasks = false,
    this.showS1Tasks = false,
    this.showChat = false,
    this.showNotifications = false,
    this.taskCount = 0,
    this.s1TasksCount = 0,
  });
}

/// الويدجت العائم القابل للسحب
class _ToolbarOverlay extends StatefulWidget {
  final ValueNotifier<_ToolbarConfig> configNotifier;
  final ValueNotifier<int> taskCountNotifier;
  final ValueNotifier<bool> shakeNotifier;
  final ValueNotifier<int> chatUnreadNotifier;
  final ValueNotifier<int> notifUnreadNotifier;
  final bool isAdmin;

  const _ToolbarOverlay({
    required this.configNotifier,
    required this.taskCountNotifier,
    required this.shakeNotifier,
    required this.chatUnreadNotifier,
    required this.notifUnreadNotifier,
    required this.isAdmin,
  });

  @override
  State<_ToolbarOverlay> createState() => _ToolbarOverlayState();
}

class _ToolbarOverlayState extends State<_ToolbarOverlay>
    with SingleTickerProviderStateMixin {
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

        // زر الإشعارات
        if (config.showNotifications) {
          buttons.add(_buildNotificationsBtn(context));
        }

        // زر المحادثة الداخلية
        if (config.showChat) {
          buttons.add(_buildChatBtn(context));
        }

        // زر محادثات الواتساب
        if (config.showConversations) {
          buttons.add(_buildConversationsBtn(context, mq));
        }

        // زر المهام (النظام الأول)
        if (config.showS1Tasks) {
          buttons.add(_buildS1TasksBtn(context, config.s1TasksCount));
        }

        // زر التذاكر (FTTH) — يظهر فقط إذا مفعّل بالصلاحية
        if (config.showTasks) {
          buttons.add(ValueListenableBuilder<int>(
            valueListenable: widget.taskCountNotifier,
            builder: (_, count, __) {
              return AnimatedBuilder(
                animation: _shakeAnim,
                builder: (_, child) =>
                    Transform.rotate(angle: _shakeAnim.value, child: child),
                child: _buildTasksBtn(context, count),
              );
            },
          ));
        } else {
          // السلوك القديم: يظهر ذاتياً فقط عند وجود تذاكر
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
        }

        // زر واتساب ويب
        if (config.showWhatsApp) {
          buttons.add(_buildWhatsAppBtn(context));
        }

        // زر تحديث VPS
        if (config.showVpsSync) {
          buttons.add(_buildVpsSyncBtn(context));
        }

        if (buttons.isEmpty) return const SizedBox.shrink();

        final isMobile = Platform.isAndroid || Platform.isIOS;
        final dx = _dx ?? (mq.width - 280);
        final dy = _dy ?? (mq.height - (isMobile ? 140 : 70));

        return Positioned(
          left: dx,
          top: dy,
          child: GestureDetector(
            onPanUpdate: (d) {
              setState(() {
                _dx = (_dx ?? dx) + d.delta.dx;
                _dy = (_dy ?? dy) + d.delta.dy;
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

  // ═══════════════════════════════════════
  // أزرار الشريط
  // ═══════════════════════════════════════

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

  Widget _buildS1TasksBtn(BuildContext context, int count) {
    return Tooltip(
      message: count > 0 ? 'المهام ($count)' : 'المهام',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: const Color(0xFF43A047),
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: FloatingToolbar._s1TasksOnTap,
                  child: const Center(
                    child: Icon(Icons.task_alt_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),
              if (count > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 4)],
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTasksBtn(BuildContext context, int count) {
    return Tooltip(
      message: count > 0 ? 'تذاكر مفتوحة ($count)' : 'التذاكر',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
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
                child: const Center(
                  child: Icon(Icons.assignment_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
            if (count > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 4)],
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
       ),
      ),
    );
  }

  Widget _buildChatBtn(BuildContext context) {
    return Tooltip(
      message: 'المحادثة الداخلية',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ValueListenableBuilder<int>(
          valueListenable: widget.chatUnreadNotifier,
          builder: (_, unread, __) {
            return SizedBox(
              width: 38,
              height: 38,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Material(
                    color: const Color(0xFF1976D2),
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        final ctx = navigatorKey.currentContext;
                        if (ctx == null) return;
                        Navigator.of(ctx).push(
                          MaterialPageRoute(
                            builder: (_) => const ChatRoomsPage(),
                          ),
                        );
                      },
                      child: const Center(
                        child: Icon(Icons.forum_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                  if (unread > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 4)],
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
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

  Widget _buildNotificationsBtn(BuildContext context) {
    return Tooltip(
      message: 'الإشعارات',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ValueListenableBuilder<int>(
          valueListenable: widget.notifUnreadNotifier,
          builder: (_, unread, __) {
            return SizedBox(
              width: 38,
              height: 38,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Material(
                    color: const Color(0xFF6A1B9A),
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        _showNotificationsPanel(context);
                      },
                      child: const Center(
                        child: Icon(Icons.notifications_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                  if (unread > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 4)],
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
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

  void _showNotificationsPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationsPanel(
        onRead: () => FloatingToolbar.refreshNotifCount(),
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

/// لوحة الإشعارات — تُفتح من زر الإشعارات العائم
class _NotificationsPanel extends StatefulWidget {
  final VoidCallback? onRead;
  const _NotificationsPanel({this.onRead});

  @override
  State<_NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<_NotificationsPanel> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await NotificationApiService.instance.getMyNotifications(
        pageSize: 30,
        unreadOnly: _unreadOnly ? true : null,
      );
      if (res['success'] == true && mounted) {
        final items = res['data'] is List ? res['data'] as List : [];
        setState(() => _notifications = items.cast<Map<String, dynamic>>());
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _markAsRead(int id) async {
    await NotificationApiService.instance.markAsRead(id);
    widget.onRead?.call();
    _load();
  }

  Future<void> _markAllRead() async {
    await NotificationApiService.instance.markAllAsRead();
    widget.onRead?.call();
    _load();
  }

  IconData _typeIcon(String? type) {
    switch (type) {
      case 'RequestStatusUpdate': return Icons.task_alt_rounded;
      case 'RequestAssigned': return Icons.assignment_ind_rounded;
      case 'AgentRequest': return Icons.storefront_rounded;
      case 'ChatMessage': return Icons.chat_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _typeColor(String? type) {
    switch (type) {
      case 'RequestStatusUpdate': return const Color(0xFF1565C0);
      case 'RequestAssigned': return const Color(0xFF00897B);
      case 'AgentRequest': return const Color(0xFFEF6C00);
      case 'ChatMessage': return const Color(0xFF2E7D32);
      default: return const Color(0xFF546E7A);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.notifications_rounded, color: Color(0xFF6A1B9A), size: 24),
                const SizedBox(width: 8),
                const Text('الإشعارات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A237E))),
                const Spacer(),
                FilterChip(
                  label: Text(_unreadOnly ? 'غير المقروءة' : 'الكل', style: const TextStyle(fontSize: 11)),
                  selected: _unreadOnly,
                  onSelected: (v) { setState(() => _unreadOnly = v); _load(); },
                  selectedColor: const Color(0xFF6A1B9A).withValues(alpha: 0.15),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'قراءة الكل',
                  icon: const Icon(Icons.done_all_rounded, size: 20),
                  onPressed: _markAllRead,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_off_outlined, size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 8),
                            Text('لا توجد إشعارات', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _notifications.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
                          itemBuilder: (_, i) {
                            final n = _notifications[i];
                            final isRead = n['IsRead'] == true || n['isRead'] == true;
                            final type = n['Type']?.toString() ?? n['type']?.toString();
                            final title = n['TitleAr']?.toString() ?? n['Title']?.toString() ?? n['title']?.toString() ?? '';
                            final body = n['BodyAr']?.toString() ?? n['Body']?.toString() ?? n['body']?.toString() ?? '';
                            final id = n['Id'] ?? n['id'];
                            final createdAt = DateTime.tryParse(n['CreatedAt']?.toString() ?? n['createdAt']?.toString() ?? '');
                            final color = _typeColor(type);

                            return ListTile(
                              dense: true,
                              tileColor: isRead ? null : color.withValues(alpha: 0.05),
                              leading: Container(
                                width: 38, height: 38,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_typeIcon(type), color: color, size: 20),
                              ),
                              title: Text(title, style: TextStyle(fontSize: 13, fontWeight: isRead ? FontWeight.w500 : FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(body, style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  if (createdAt != null)
                                    Text(_timeAgo(createdAt), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                ],
                              ),
                              trailing: !isRead && id != null
                                  ? IconButton(
                                      icon: Icon(Icons.check_circle_outline, size: 18, color: color),
                                      tooltip: 'قراءة',
                                      onPressed: () => _markAsRead(id is int ? id : int.tryParse(id.toString()) ?? 0),
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
    if (diff.inDays < 7) return 'قبل ${diff.inDays} يوم';
    return '${dt.day}/${dt.month}';
  }
}
