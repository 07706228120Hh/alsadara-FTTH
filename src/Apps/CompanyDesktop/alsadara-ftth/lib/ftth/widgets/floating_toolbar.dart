import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/chat_service.dart';
import '../../services/notification_api_service.dart';
import '../../services/ticket_updates_service.dart';
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
  static bool _showTasks = false;
  static bool _showS1Tasks = false;
  static bool _showChat = false;
  static bool _showNotifications = false;
  static bool _isAdmin = false;

  // callback للمهام (النظام الأول)
  static VoidCallback? _s1TasksOnTap;
  static int _s1TasksCount = 0;

  // تتبع الصفحة المفتوحة حالياً
  static String? _currentOpenPage;
  static bool _isNavigating = false; // حماية من الضغط المتكرر

  // حالة الطي/الفتح
  static final ValueNotifier<bool> _collapsedNotifier = ValueNotifier<bool>(false);

  // إشعار shake لزر معين
  static final ValueNotifier<String?> _shakeButtonNotifier = ValueNotifier<String?>(null);

  // notifiers
  static final ValueNotifier<int> _taskCount = ValueNotifier<int>(0);
  static final ValueNotifier<bool> _shakeNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<int> _chatUnreadCount = ValueNotifier<int>(0);
  static final ValueNotifier<int> _notifUnreadCount = ValueNotifier<int>(0);
  static final ValueNotifier<int> _waUnreadCount = ValueNotifier<int>(0);
  static final ValueNotifier<_ToolbarConfig> _configNotifier =
      ValueNotifier<_ToolbarConfig>(_ToolbarConfig());

  static StreamSubscription? _taskCountSub;
  static StreamSubscription? _newTicketsSub;
  static StreamSubscription? _chatUnreadSub;
  static StreamSubscription? _waUnreadSub;
  static Timer? _notifTimer;

  // ═══ SharedPreferences keys ═══
  static const _keyCollapsed = 'floating_toolbar_collapsed';
  static const _keyDx = 'floating_toolbar_dx';
  static const _keyDy = 'floating_toolbar_dy';

  /// تحميل الحالة المحفوظة
  static Future<void> _loadSavedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _collapsedNotifier.value = prefs.getBool(_keyCollapsed) ?? false;
    } catch (_) {}
  }

  /// حفظ حالة الطي
  static Future<void> _saveCollapsed(bool collapsed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyCollapsed, collapsed);
    } catch (_) {}
  }

  /// حفظ الموقع
  static Future<void> savePosition(double dx, double dy) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyDx, dx);
      await prefs.setDouble(_keyDy, dy);
    } catch (_) {}
  }

  /// تحميل الموقع المحفوظ
  static Future<(double?, double?)> loadPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dx = prefs.getDouble(_keyDx);
      final dy = prefs.getDouble(_keyDy);
      return (dx, dy);
    } catch (_) {
      return (null, null);
    }
  }

  /// طي/فتح الشريط
  static void toggleCollapsed() {
    _collapsedNotifier.value = !_collapsedNotifier.value;
    _saveCollapsed(_collapsedNotifier.value);
  }

  /// إغلاق الصفحة المفتوحة حالياً
  static void _closeCurrentPage() {
    if (_currentOpenPage == null) return;
    _currentOpenPage = null;
    try {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && Navigator.of(ctx).canPop()) {
        Navigator.of(ctx).pop();
      }
    } catch (_) {}
  }

  /// فتح/إغلاق صفحة — نفس الزر يفتح ويغلق
  static void _openPage(String pageName, VoidCallback openAction) {
    if (_isNavigating) return;

    // نفس الصفحة مفتوحة → أغلقها فقط (toggle)
    if (_currentOpenPage == pageName) {
      _closeCurrentPage();
      return;
    }

    _isNavigating = true;

    // صفحة مختلفة مفتوحة → أغلقها أولاً
    if (_currentOpenPage != null) {
      _closeCurrentPage();
    }

    // فتح الصفحة الجديدة بعد frame واحد لضمان اكتمال الإغلاق
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _currentOpenPage = pageName;
      openAction();
      // السماح بالضغط مجدداً بعد فترة
      Future.delayed(const Duration(milliseconds: 500), () {
        _isNavigating = false;
      });
    });
  }

  /// إعلام بإغلاق الصفحة (عند الرجوع بزر back أو سحب)
  static void notifyPageClosed() {
    _currentOpenPage = null;
    _isNavigating = false;
  }

  /// تشغيل shake لزر معين
  static void _triggerButtonShake(String buttonName) {
    _shakeButtonNotifier.value = buttonName;
    Future.delayed(const Duration(milliseconds: 800), () {
      if (_shakeButtonNotifier.value == buttonName) {
        _shakeButtonNotifier.value = null;
      }
    });
  }

  /// عدد الإشعارات الإجمالي من كل الأزرار
  static int get totalBadgeCount =>
      _taskCount.value + _s1TasksCount + _chatUnreadCount.value +
      _notifUnreadCount.value + _waUnreadCount.value;

  /// تهيئة الشريط العائم — يُستدعى من home_page
  static void init(BuildContext context) {
    try {
      _rootOverlay = Overlay.of(context, rootOverlay: true);
    } catch (e) {
      debugPrint('[FloatingToolbar] init overlay failed');
      return;
    }

    _loadSavedState();

    WhatsAppBottomWindow.suppressIndividualFabs = true;
    WhatsAppBottomWindow.removeAllFabs();
    AgentTasksBubble.suppressIndividualBubble = true;

    // الاشتراك في عدد تاسكات الوكيل
    _taskCountSub?.cancel();
    _taskCountSub =
        TicketUpdatesService.instance.agentTaskCountStream.listen((count) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final old = _taskCount.value;
        _taskCount.value = count;
        if (count > old && old >= 0) _triggerButtonShake('ftth_tickets');
        _refreshConfig();
      });
    });

    _newTicketsSub?.cancel();
    _newTicketsSub =
        TicketUpdatesService.instance.newTicketsStream.listen((newTasks) {
      if (newTasks.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _shakeNotifier.value = true;
          _triggerButtonShake('ftth_tickets');
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

  static void enableWhatsApp() {
    _showWhatsApp = true;
    _scheduleRefresh();
  }

  static void enableConversations({bool isAdmin = false}) {
    _showConversations = true;
    _isAdmin = isAdmin;
    // الاشتراك في عدد واتساب غير المقروء
    _waUnreadSub?.cancel();
    _waUnreadSub = WhatsAppConversationService.getUnreadCount().listen((count) {
      final old = _waUnreadCount.value;
      _waUnreadCount.value = count;
      if (count > old && old >= 0) _triggerButtonShake('conversations');
    });
    _scheduleRefresh();
  }

  static void disableConversations() {
    _showConversations = false;
    _waUnreadSub?.cancel();
    _waUnreadSub = null;
    _scheduleRefresh();
  }

  static void enableTasks() {
    _showTasks = true;
    _scheduleRefresh();
  }

  static void disableTasks() {
    _showTasks = false;
    _scheduleRefresh();
  }

  static void enableS1Tasks({required VoidCallback onTap, int badgeCount = 0}) {
    _showS1Tasks = true;
    _s1TasksOnTap = onTap;
    _s1TasksCount = badgeCount;
    _scheduleRefresh();
  }

  static void updateS1TasksBadge(int count) {
    final old = _s1TasksCount;
    _s1TasksCount = count;
    if (count > old && old >= 0) _triggerButtonShake('s1tasks');
    _scheduleRefresh();
  }

  static void reEnableS1Tasks() {
    if (_s1TasksOnTap != null) {
      _showS1Tasks = true;
      _scheduleRefresh();
    }
  }

  static void disableS1Tasks() {
    _showS1Tasks = false;
    _s1TasksOnTap = null;
    _s1TasksCount = 0;
    _scheduleRefresh();
  }

  static void enableChat() {
    _showChat = true;
    _chatUnreadSub?.cancel();
    _chatUnreadSub = ChatService.instance.onUnreadCount.listen((count) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final old = _chatUnreadCount.value;
        _chatUnreadCount.value = count;
        if (count > old && old >= 0) _triggerButtonShake('chat');
      });
    });
    ChatService.instance.refreshUnreadCount();
    _scheduleRefresh();
  }

  static void disableChat() {
    _showChat = false;
    _chatUnreadSub?.cancel();
    _chatUnreadSub = null;
    _scheduleRefresh();
  }

  static void enableNotifications() {
    _showNotifications = true;
    _notifTimer?.cancel();
    _fetchNotifCount();
    _notifTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchNotifCount();
    });
    _scheduleRefresh();
  }

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
          final old = _notifUnreadCount.value;
          _notifUnreadCount.value = count;
          if (count > old && old >= 0) _triggerButtonShake('notifications');
        });
      }
    } catch (_) {}
  }

  static void refreshNotifCount() => _fetchNotifCount();

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
    final hasAny = _showWhatsApp || _showConversations || _showTasks ||
        _showS1Tasks || _showChat || _showNotifications;
    _configNotifier.value = _ToolbarConfig(
      showWhatsApp: _showWhatsApp,
      showConversations: _showConversations,
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
      shakeButtonNotifier: _shakeButtonNotifier,
      chatUnreadNotifier: _chatUnreadCount,
      notifUnreadNotifier: _notifUnreadCount,
      waUnreadNotifier: _waUnreadCount,
      collapsedNotifier: _collapsedNotifier,
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
    _waUnreadSub?.cancel();
    _notifTimer?.cancel();
    _notifTimer = null;
    _chatUnreadSub = null;
    _waUnreadSub = null;
    _hide();
    _rootOverlay = null;
    _showWhatsApp = false;
    _showConversations = false;
    _showTasks = false;
    _showS1Tasks = false;
    _s1TasksOnTap = null;
    _s1TasksCount = 0;
    _showChat = false;
    _showNotifications = false;
    _currentOpenPage = null;
    _isNavigating = false;
    _refreshScheduled = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _taskCount.value = 0;
      _chatUnreadCount.value = 0;
      _notifUnreadCount.value = 0;
      _waUnreadCount.value = 0;
    });
    WhatsAppBottomWindow.suppressIndividualFabs = false;
    AgentTasksBubble.suppressIndividualBubble = false;
  }
}

class _ToolbarConfig {
  final bool showWhatsApp;
  final bool showConversations;
  final bool showTasks;
  final bool showS1Tasks;
  final bool showChat;
  final bool showNotifications;
  final int taskCount;
  final int s1TasksCount;
  _ToolbarConfig({
    this.showWhatsApp = false,
    this.showConversations = false,
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
  final ValueNotifier<String?> shakeButtonNotifier;
  final ValueNotifier<int> chatUnreadNotifier;
  final ValueNotifier<int> notifUnreadNotifier;
  final ValueNotifier<int> waUnreadNotifier;
  final ValueNotifier<bool> collapsedNotifier;
  final bool isAdmin;

  const _ToolbarOverlay({
    required this.configNotifier,
    required this.taskCountNotifier,
    required this.shakeNotifier,
    required this.shakeButtonNotifier,
    required this.chatUnreadNotifier,
    required this.notifUnreadNotifier,
    required this.waUnreadNotifier,
    required this.collapsedNotifier,
    required this.isAdmin,
  });

  @override
  State<_ToolbarOverlay> createState() => _ToolbarOverlayState();
}

class _ToolbarOverlayState extends State<_ToolbarOverlay>
    with TickerProviderStateMixin {
  double? _dx;
  double? _dy;
  bool _positionLoaded = false;

  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  // shake controllers لكل زر
  final Map<String, AnimationController> _btnShakeControllers = {};

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
    widget.shakeButtonNotifier.addListener(_onButtonShake);

    _loadPosition();
  }

  Future<void> _loadPosition() async {
    final (dx, dy) = await FloatingToolbar.loadPosition();
    if (mounted && (dx != null || dy != null)) {
      setState(() {
        _dx = dx;
        _dy = dy;
        _positionLoaded = true;
      });
    } else {
      _positionLoaded = true;
    }
  }

  AnimationController _getOrCreateShakeCtrl(String name) {
    if (!_btnShakeControllers.containsKey(name)) {
      _btnShakeControllers[name] = AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      );
    }
    return _btnShakeControllers[name]!;
  }

  Animation<double> _buildShakeAnimation(AnimationController ctrl) {
    return TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 0.9), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.15), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
  }

  void _onShake() {
    if (widget.shakeNotifier.value) {
      _shakeCtrl.forward(from: 0.0);
    }
  }

  void _onButtonShake() {
    final name = widget.shakeButtonNotifier.value;
    if (name != null) {
      final ctrl = _getOrCreateShakeCtrl(name);
      ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    widget.shakeNotifier.removeListener(_onShake);
    widget.shakeButtonNotifier.removeListener(_onButtonShake);
    _shakeCtrl.dispose();
    for (final c in _btnShakeControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _openToolbarPage(String name, Widget page) {
    FloatingToolbar._openPage(name, () {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      Navigator.of(ctx).push(
        MaterialPageRoute(builder: (_) => page),
      ).then((_) => FloatingToolbar.notifyPageClosed());
    });
  }

  void _openToolbarPageInstant(String name, Widget page) {
    FloatingToolbar._openPage(name, () {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      Navigator.of(ctx).push(
        PageRouteBuilder(
          pageBuilder: (c, a, b) => page,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (c, a, b, child) => child,
        ),
      ).then((_) => FloatingToolbar.notifyPageClosed());
    });
  }

  Widget _buildBadge(int count) {
    if (count <= 0) return const SizedBox.shrink();
    return Positioned(
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
    );
  }

  /// بناء زر دائري مع دعم shake
  Widget _buildCircleBtn({
    required String name,
    required String tooltip,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
    int badge = 0,
    double btnSize = 38,
    double iconSize = 18,
  }) {
    final ctrl = _getOrCreateShakeCtrl(name);
    final scaleAnim = _buildShakeAnimation(ctrl);

    return AnimatedBuilder(
      animation: scaleAnim,
      builder: (_, child) => Transform.scale(scale: scaleAnim.value, child: child),
      child: Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: SizedBox(
            width: btnSize,
            height: btnSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Material(
                  color: color,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onTap,
                    child: Center(
                      child: Icon(icon, color: Colors.white, size: iconSize),
                    ),
                  ),
                ),
                _buildBadge(badge),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // _dx = المسافة من اليمين (right)، _dy = المسافة من الأعلى (top)
  void _onDragUpdate(DragUpdateDetails d, double maxW, double maxH, bool isMobile) {
    setState(() {
      final defaultRight = isMobile ? 10.0 : 20.0;
      final defaultDy = maxH - (isMobile ? 120.0 : 70.0);
      final currentRight = _dx ?? defaultRight;
      final currentDy = _dy ?? defaultDy;
      // dx = right: السحب لليمين يقلل right، والعكس
      _dx = (currentRight - d.delta.dx).clamp(0.0, maxW - 60);
      _dy = (currentDy + d.delta.dy).clamp(40.0, maxH - (isMobile ? 100 : 60));
    });
  }

  void _onDragEnd() {
    if (_dx != null && _dy != null) {
      FloatingToolbar.savePosition(_dx!, _dy!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context).size;
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final btnSize = isMobile ? 34.0 : 38.0;
    final iconSize = isMobile ? 16.0 : 18.0;

    return ValueListenableBuilder<bool>(
      valueListenable: widget.collapsedNotifier,
      builder: (_, collapsed, __) {
        return ValueListenableBuilder<_ToolbarConfig>(
          valueListenable: widget.configNotifier,
          builder: (_, config, __) {
            final defaultRight = isMobile ? 10.0 : 20.0;
            final right = _dx ?? defaultRight;
            final dy = _dy ?? (mq.height - (isMobile ? 120 : 70));

            if (collapsed) {
              return _buildCollapsedToolbar(right, dy, mq, isMobile);
            }
            return _buildExpandedToolbar(config, right, dy, mq, isMobile, btnSize, iconSize);
          },
        );
      },
    );
  }

  /// الشريط المطوي — أيقونة واحدة مع نقطة إشعار
  Widget _buildCollapsedToolbar(double right, double dy, Size mq, bool isMobile) {
    return Positioned(
      right: right,
      top: dy,
      child: GestureDetector(
        onPanUpdate: (d) => _onDragUpdate(d, mq.width, mq.height, isMobile),
        onPanEnd: (_) => _onDragEnd(),
        onTap: FloatingToolbar.toggleCollapsed,
        child: ValueListenableBuilder<int>(
          valueListenable: widget.taskCountNotifier,
          builder: (_, taskCount, __) {
            return ValueListenableBuilder<int>(
              valueListenable: widget.chatUnreadNotifier,
              builder: (_, chatUnread, __) {
                return ValueListenableBuilder<int>(
                  valueListenable: widget.notifUnreadNotifier,
                  builder: (_, notifUnread, __) {
                    return ValueListenableBuilder<int>(
                      valueListenable: widget.waUnreadNotifier,
                      builder: (_, waUnread, __) {
                        final total = taskCount + FloatingToolbar._s1TasksCount +
                            chatUnread + notifUnread + waUnread;
                        return Material(
                          elevation: 8,
                          shape: const CircleBorder(),
                          color: const Color(0xFF1A237E),
                          shadowColor: Colors.black38,
                          child: SizedBox(
                            width: isMobile ? 44 : 50,
                            height: isMobile ? 44 : 50,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Center(
                                  child: Icon(Icons.apps_rounded, color: Colors.white, size: 22),
                                ),
                                if (total > 0)
                                  Positioned(
                                    top: -2,
                                    right: -2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.5), blurRadius: 6)],
                                      ),
                                      constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
                                      child: Text(
                                        total > 99 ? '99+' : '$total',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// الشريط الموسّع — كل الأزرار
  Widget _buildExpandedToolbar(_ToolbarConfig config, double right, double dy,
      Size mq, bool isMobile, double btnSize, double iconSize) {
    final buttons = <Widget>[];

    if (config.showNotifications) {
      buttons.add(ValueListenableBuilder<int>(
        valueListenable: widget.notifUnreadNotifier,
        builder: (_, unread, __) => _buildCircleBtn(
          name: 'notifications',
          tooltip: unread > 0 ? 'الإشعارات ($unread)' : 'الإشعارات',
          color: const Color(0xFF6A1B9A),
          icon: Icons.notifications_rounded,
          badge: unread,
          btnSize: btnSize,
          iconSize: iconSize,
          onTap: () => _showNotificationsPanel(context),
        ),
      ));
    }

    if (config.showChat) {
      buttons.add(ValueListenableBuilder<int>(
        valueListenable: widget.chatUnreadNotifier,
        builder: (_, unread, __) => _buildCircleBtn(
          name: 'chat',
          tooltip: unread > 0 ? 'المحادثة ($unread)' : 'المحادثة الداخلية',
          color: const Color(0xFF1976D2),
          icon: Icons.forum_rounded,
          badge: unread,
          btnSize: btnSize,
          iconSize: iconSize + 2,
          onTap: () => _openToolbarPage('chat', const ChatRoomsPage()),
        ),
      ));
    }

    if (config.showConversations) {
      buttons.add(ValueListenableBuilder<int>(
        valueListenable: widget.waUnreadNotifier,
        builder: (_, unread, __) => _buildCircleBtn(
          name: 'conversations',
          tooltip: unread > 0 ? 'واتساب خاص ($unread)' : 'واتساب خاص',
          color: const Color(0xFF128C7E),
          icon: Icons.chat_bubble,
          badge: unread,
          btnSize: btnSize,
          iconSize: iconSize,
          onTap: () {
            if (conv_page.WhatsAppConversationsPage.isOpen) return;
            _openToolbarPage('conversations',
              conv_page.WhatsAppConversationsPage(isAdmin: widget.isAdmin));
          },
        ),
      ));
    }

    if (config.showS1Tasks) {
      buttons.add(_buildCircleBtn(
        name: 's1tasks',
        tooltip: config.s1TasksCount > 0 ? 'المهام (${config.s1TasksCount})' : 'المهام',
        color: const Color(0xFF43A047),
        icon: Icons.task_alt_rounded,
        badge: config.s1TasksCount,
        btnSize: btnSize,
        iconSize: iconSize + 2,
        onTap: () {
          if (FloatingToolbar._s1TasksOnTap != null) {
            FloatingToolbar._closeCurrentPage();
            FloatingToolbar._currentOpenPage = 's1tasks';
            FloatingToolbar._s1TasksOnTap!();
          }
        },
      ));
    }

    if (config.showTasks) {
      buttons.add(ValueListenableBuilder<int>(
        valueListenable: widget.taskCountNotifier,
        builder: (_, count, __) {
          return AnimatedBuilder(
            animation: _shakeAnim,
            builder: (_, child) =>
                Transform.rotate(angle: _shakeAnim.value, child: child),
            child: _buildCircleBtn(
              name: 'ftth_tickets',
              tooltip: count > 0 ? 'تذاكر مفتوحة ($count)' : 'التذاكر',
              color: Colors.orange.shade700,
              icon: Icons.assignment_rounded,
              badge: count,
              btnSize: btnSize,
              iconSize: iconSize + 2,
              onTap: () {
                final token = TicketUpdatesService.instance.currentToken;
                if (token == null || token.isEmpty) return;
                _openToolbarPageInstant('ftth_tickets',
                  TKTATsPage(authToken: token, initialTab: 'open'));
              },
            ),
          );
        },
      ));
    }

    if (config.showWhatsApp) {
      buttons.add(_buildCircleBtn(
        name: 'whatsapp',
        tooltip: 'واتساب عادي',
        color: const Color(0xFF25D366),
        icon: Icons.chat,
        btnSize: btnSize,
        iconSize: iconSize,
        onTap: () {
          WhatsAppBottomWindow.showBottomWindow(context, '', '');
        },
      ));
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Positioned(
      right: right,
      top: dy,
      child: GestureDetector(
        onPanUpdate: (d) => _onDragUpdate(d, mq.width, mq.height, isMobile),
        onPanEnd: (_) => _onDragEnd(),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(24),
          color: Colors.white.withValues(alpha: 0.95),
          shadowColor: Colors.black38,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 5 : 8,
              vertical: isMobile ? 3 : 4,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.shade300, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // زر الطي
                GestureDetector(
                  onTap: FloatingToolbar.toggleCollapsed,
                  child: Icon(Icons.keyboard_arrow_left_rounded,
                      size: isMobile ? 18 : 22, color: Colors.grey.shade500),
                ),
                SizedBox(width: isMobile ? 1 : 2),
                // أيقونة السحب
                Icon(Icons.drag_indicator,
                    size: isMobile ? 14 : 18, color: Colors.grey.shade400),
                SizedBox(width: isMobile ? 1 : 2),
                ...buttons,
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNotificationsPanel(BuildContext context) {
    FloatingToolbar._closeCurrentPage();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationsPanel(
        onRead: () => FloatingToolbar.refreshNotifCount(),
      ),
    );
  }
}

/// لوحة الإشعارات
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
