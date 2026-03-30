import 'dart:async';
import 'dart:io';
// (تمت إزالة استيراد dart:convert لعدم الحاجة حالياً)
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as wvwin;
import 'package:url_launcher/url_launcher.dart';
import '../../pages/whatsapp_conversations_page.dart' as conv_page;
import '../../services/whatsapp_conversation_service.dart';

/// نافذة واتساب كاملة الحجم
class WhatsAppBottomWindow {
  static OverlayEntry? _overlayEntry;
  static OverlayEntry? _fabEntry;
  static OverlayEntry? _conversationsFabEntry; // زر عائم للمحادثات
  static bool _isShowing = false;
  static bool _isHidden = false;
  static Timer? _fabGuardTimer; // مراقبة لضمان بقاء زر الواتساب
  static OverlayState? _rootOverlay; // overlay الجذرية لتثبيت العناصر عالمياً
  static bool _initialized = false; // تم التهيئة الجذرية
  /// عند true، لا تُنشأ أزرار FAB فردية (FloatingToolbar يتولى المهمة)
  static bool suppressIndividualFabs = false;
  // _isHidden == true يعني أننا في حالة تصغير (Minimized) لكن ما زال الـ WebView موجود في الذاكرة
  static _WhatsAppBottomWindowState? _instance;
  static BuildContext? _savedContext;
  static Widget? _savedWindowContent; // حفظ محتوى النافذة لإعادة الاستخدام
  static final GlobalKey<_WhatsAppBottomWindowState> _windowKey =
      GlobalKey<_WhatsAppBottomWindowState>(); // مفتاح للحفاظ على الحالة
  static bool _isAdminUser = false; // حالة المدير

  /// التحقق من وجود نافذة مخفية
  static bool get hasHiddenWindow =>
      _isShowing && _isHidden && _savedWindowContent != null;

  /// إظهار نافذة واتساب بحجم كامل
  static void showBottomWindow(
      BuildContext context, String phone, String message,
      {bool autoSend = false}) {
    // تأكد من التهيئة الجذرية
    ensureGlobal(context);
    _savedContext = context;

    debugPrint(
        '🔍 showBottomWindow called: _isShowing=$_isShowing, _isHidden=$_isHidden, autoSend=$autoSend');

    // إذا كانت النافذة مخفية، أظهرها مع المحتوى المحفوظ
    if (_isShowing && _isHidden && _savedWindowContent != null) {
      // استرجاع سريع دون إعادة تحميل كامل
      _restoreMinimizedWindow();
      if (phone.isNotEmpty && message.isNotEmpty) {
        // استخدم المسار الذكي (سيراعي نفس المحادثة)
        sendMessageToBottomWindow(phone, message, autoSend: autoSend);
      }
      return;
    }

    if (_isShowing && !_isHidden) {
      if (phone.isNotEmpty && message.isNotEmpty) {
        sendMessageToBottomWindow(phone, message, autoSend: autoSend);
      }
      return;
    }

    // إنشاء نافذة جديدة فقط إذا لم تكن موجودة
    _savedWindowContent ??= WhatsAppBottomWindowContent(
      key: _windowKey,
      phone: phone,
      message: message,
      autoSend: autoSend,
      onClose: _closeWindow, // إغلاق نهائي
      onMinimize: _minimizeWindow, // تصغير فقط
    );

    _overlayEntry = OverlayEntry(
        builder: (context) => IgnorePointer(
              ignoring:
                  _isHidden, // السماح بالنقر على العناصر أسفل النافذة عند التصغير
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isHidden ? 0.0 : 1.0,
                child: Material(
                  child: Container(
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                    color: Colors.white,
                    child: _savedWindowContent!,
                  ),
                ),
              ),
            ));

    final overlay = _rootOverlay ?? Overlay.of(context, rootOverlay: true);
    overlay.insert(_overlayEntry!);
    _isShowing = true;
    _isHidden = false;

    // تأكد من وجود زر الواتساب دائماً (حتى أثناء فتح النافذة)
    // إظهار الزر العائم (عالمي) إن لم يكن موجوداً
    if (_fabEntry == null) {
      showFloatingButton(context);
    }
  }

  /// إخفاء النافذة
  static void hideBottomWindow({bool clearContent = false}) {
    try {
      if (_overlayEntry != null) {
        _overlayEntry!.remove();
        _overlayEntry = null;
      }
    } catch (e) {
      debugPrint('⚠️ Error removing main overlay');
      _overlayEntry = null;
    }

    try {
      if (_fabEntry != null) {
        _fabEntry!.remove();
        _fabEntry = null;
      }
    } catch (e) {
      debugPrint('⚠️ Error removing FAB overlay');
      _fabEntry = null;
    }

    // إعادة تعيين جميع الحالات
    _isShowing = false;
    _isHidden = false;

    // مسح المحتوى فقط عند الإغلاق النهائي (clearContent = true)
    if (clearContent) {
      _instance = null;
      _savedContext = null;
      _savedWindowContent = null;
      _stopFabGuard();
    }
  }

  /// تصغير النافذة وإظهار الزر العائم
  static void _minimizeWindow() {
    if (!_isShowing) return;
    if (_isHidden) return; // بالفعل مصغرة
    _isHidden = true;
    // تحديث الـ overlay بدون إزالة الـ WebView للحفاظ على الجلسة
    _overlayEntry?.markNeedsBuild();

    // إظهار الزر العائم
    if (_savedContext != null) {
      try {
        if (_savedContext!.mounted) {
          showFloatingButton(_savedContext!);
        } else {
          debugPrint('⚠️ Saved context is not mounted, cannot show FAB');
        }
      } catch (e) {
        debugPrint('⚠️ Error showing FAB after minimize');
      }
    }
  }

  /// إرجاع النافذة المصغرة بدون إعادة تحميل أو فقدان الحالة
  static void _restoreMinimizedWindow() {
    if (!_isShowing || !_isHidden) return;
    _isHidden = false;
    _overlayEntry?.markNeedsBuild();
    // لا نقوم بإزالة زر الواتساب لإبقائه دائماً
    if (_fabEntry == null && _savedContext != null) {
      try {
        if (_savedContext!.mounted) {
          showFloatingButton(_savedContext!);
        }
      } catch (_) {}
    }
  }

  /// إغلاق نهائي مع تنظيف الحالة بالكامل
  static void _closeWindow() {
    hideBottomWindow(clearContent: true);
  }

  /// ضمان وجود زر الواتساب بعد الانتقال بين أنظمة / صفحات مختلفة
  /// استدعها من الشاشة الرئيسية لكل نظام (في build أو بعد الانتقال) لضمان إعادة إظهار الزر إذا فُقد الـ Overlay القديم.
  static void ensureFloatingButton(BuildContext context) {
    if (suppressIndividualFabs) return; // FloatingToolbar يتولى المهمة
    ensureGlobal(context);
    _savedContext = context;
    // إذا كان لدينا زر مفقود (null) أو تم التخلص من الـ overlay السابق (يحصل بعد تغيير Navigator)
    bool needsRecreate = false;
    if (_fabEntry == null) {
      needsRecreate = true;
    } else {
      // محاولة تحفيز إعادة بناء؛ لو حصل خطأ نعيد إنشاؤه
      try {
        _fabEntry!.markNeedsBuild();
      } catch (e) {
        debugPrint('⚠️ FAB overlay seems detached, recreating');
        try {
          _fabEntry!.remove();
        } catch (_) {}
        _fabEntry = null;
        needsRecreate = true;
      }
    }
    if (needsRecreate) {
      showFloatingButton(context);
    }
  }

  /// إظهار النافذة المخفية مع المحتوى المحفوظ
  // (تم إلغاء الدالة القديمة _showExistingWindow لعدم الحاجة)

  /// إظهار الزر العائم
  static void showFloatingButton(BuildContext context) {
    if (suppressIndividualFabs) return; // FloatingToolbar يتولى المهمة
    // تهيئة جذرية إذا لم تتم
    ensureGlobal(context);
    // إذا كان موجوداً ومثبتاً (mounted) لا نعيد إنشاءه، فقط نضمن الحارس
    if (_fabEntry != null && _fabEntry!.mounted) {
      _startFabGuard();
      return;
    }
    // إن كان غير مثبت أو null نحذفه وننشئ واحد جديد
    if (_fabEntry != null && !_fabEntry!.mounted) {
      try {
        _fabEntry!.remove();
      } catch (_) {}
      _fabEntry = null;
    }

    // التحقق من أن الـ context ما زال صالحاً
    try {
      if (!context.mounted) {
        debugPrint('⚠️ Context is not mounted, cannot show FAB');
        return;
      }
    } catch (e) {
      debugPrint('⚠️ Context error');
      return;
    }

    _fabEntry = OverlayEntry(
      builder: (context) {
        final mq = MediaQuery.of(context).size;
        final isPhone = mq.width < 600;
        final isTablet = mq.width >= 600 && mq.width < 1024;
        final fabSize = isPhone
            ? 44.0
            : isTablet
                ? 52.0
                : 56.0;
        final iconSize = isPhone
            ? 20.0
            : isTablet
                ? 24.0
                : 28.0;
        final innerSize = isPhone
            ? 28.0
            : isTablet
                ? 33.0
                : 38.0;
        final bottomPos = isPhone
            ? 24.0
            : isTablet
                ? 40.0
                : 80.0;
        final rightPos = isPhone
            ? 12.0
            : isTablet
                ? 16.0
                : 20.0;
        return Positioned(
          bottom: bottomPos,
          right: rightPos,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(fabSize / 2),
            child: SizedBox(
              width: fabSize,
              height: fabSize,
              child: FloatingActionButton(
                onPressed: () {
                  try {
                    debugPrint('🔘 ضغط زر واتساب العائم');
                    if (_isShowing && _isHidden) {
                      _restoreMinimizedWindow();
                      debugPrint('✅ تم استرجاع النافذة المصغرة');
                    } else {
                      showBottomWindow(context, '', '');
                      debugPrint('✅ تم فتح/إظهار نافذة الواتساب');
                    }
                  } catch (e) {
                    debugPrint('❌ خطأ في التعامل مع زر الواتساب العائم');
                  }
                },
                backgroundColor: const Color(0xFF25D366),
                heroTag: "whatsapp_fab",
                tooltip: 'فتح واتساب ويب',
                child: Container(
                  width: innerSize,
                  height: innerSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(innerSize / 2),
                    color: Colors.white,
                  ),
                  child: Icon(
                    Icons.chat,
                    color: const Color(0xFF25D366),
                    size: iconSize,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    try {
      final overlay = _rootOverlay ?? Overlay.of(context, rootOverlay: true);
      overlay.insert(_fabEntry!);
    } catch (e) {
      debugPrint('⚠️ Failed to insert FAB overlay');
      _fabEntry = null;
    }

    _startFabGuard();
  }

  /// إظهار زر عائم للمحادثات (على الجهة اليسرى)
  static void showConversationsFloatingButton(BuildContext context,
      {bool isAdmin = false}) {
    if (suppressIndividualFabs) return; // FloatingToolbar يتولى المهمة
    _isAdminUser = isAdmin; // حفظ حالة المدير
    debugPrint('👤 showConversationsFloatingButton - isAdmin: $isAdmin');
    if (_conversationsFabEntry != null) {
      _conversationsFabEntry?.remove();
      _conversationsFabEntry = null;
    }

    // التحقق من أن الـ context ما زال صالحاً
    try {
      if (!context.mounted) {
        debugPrint('⚠️ Context is not mounted, cannot show Conversations FAB');
        return;
      }
    } catch (e) {
      debugPrint('⚠️ Context error');
      return;
    }

    _conversationsFabEntry = OverlayEntry(
      builder: (context) {
        final mq = MediaQuery.of(context).size;
        final isPhone = mq.width < 600;
        final isTablet = mq.width >= 600 && mq.width < 1024;
        final fabSize = isPhone
            ? 44.0
            : isTablet
                ? 52.0
                : 56.0;
        final iconSize = isPhone
            ? 20.0
            : isTablet
                ? 24.0
                : 28.0;
        final innerSize = isPhone
            ? 28.0
            : isTablet
                ? 33.0
                : 38.0;
        final bottomPos = isPhone
            ? 24.0
            : isTablet
                ? 40.0
                : 80.0;
        final leftPos = isPhone
            ? 12.0
            : isTablet
                ? 16.0
                : 20.0;
        final badgeSize = isPhone ? 16.0 : 20.0;
        final badgeFontSize = isPhone ? 8.0 : 10.0;
        return Positioned(
          bottom: bottomPos,
          left: leftPos,
          child: StreamBuilder<int>(
            stream: WhatsAppConversationService.getUnreadCount(),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;
              return Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(fabSize / 2),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    SizedBox(
                      width: fabSize,
                      height: fabSize,
                      child: FloatingActionButton(
                        onPressed: () {
                          try {
                            if (conv_page.WhatsAppConversationsPage.isOpen) {
                              debugPrint('📌 صفحة المحادثات مفتوحة بالفعل');
                              return;
                            }
                            debugPrint('🔘 ضغط زر المحادثات العائم');
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    conv_page.WhatsAppConversationsPage(
                                        isAdmin: _isAdminUser),
                              ),
                            );
                          } catch (e) {
                            debugPrint('❌ خطأ في فتح صفحة المحادثات');
                          }
                        },
                        backgroundColor: const Color(0xFF128C7E),
                        heroTag: "whatsapp_conversations_fab",
                        tooltip: 'محادثات الواتساب',
                        child: Container(
                          width: innerSize,
                          height: innerSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(innerSize / 2),
                            color: Colors.white,
                          ),
                          child: Icon(
                            Icons.chat_bubble,
                            color: const Color(0xFF128C7E),
                            size: iconSize,
                          ),
                        ),
                      ),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: -5,
                        right: -5,
                        child: Container(
                          padding: EdgeInsets.all(isPhone ? 3 : 4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: BoxConstraints(
                            minWidth: badgeSize,
                            minHeight: badgeSize,
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: badgeFontSize,
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
        );
      },
    );

    try {
      final overlay = _rootOverlay ?? Overlay.of(context, rootOverlay: true);
      overlay.insert(_conversationsFabEntry!);
    } catch (e) {
      debugPrint('⚠️ Failed to insert Conversations FAB overlay');
      _conversationsFabEntry = null;
    }
  }

  /// إخفاء زر المحادثات العائم
  static void hideConversationsFloatingButton() {
    _conversationsFabEntry?.remove();
    _conversationsFabEntry = null;
  }

  /// إزالة جميع الأزرار العائمة الفردية (يُستدعى من FloatingToolbar)
  static void removeAllFabs() {
    _stopFabGuard();
    try { _fabEntry?.remove(); } catch (_) {}
    _fabEntry = null;
    try { _conversationsFabEntry?.remove(); } catch (_) {}
    _conversationsFabEntry = null;
  }

  /// فحص إذا كانت النافذة مفتوحة
  static bool isBottomWindowShowing() {
    return _isShowing && _instance != null;
  }

  /// إرسال رسالة للنافذة المفتوحة
  static bool sendMessageToBottomWindow(String phone, String message,
      {bool autoSend = false}) {
    if (_isShowing && _instance != null) {
      try {
        // إذا كنا في نفس المحادثة الحالية (نفس الرقم) نحاول حقن رسالة بدون إعادة تحميل كامل
        if (_instance!._currentPhone.isNotEmpty &&
            phone == _instance!._currentPhone) {
          debugPrint(
              '💬 إرسال رسالة إضافية في نفس المحادثة بدون إعادة تحميل (auto send: $autoSend)');
          _instance!.sendAnotherMessageSameChat(message, autoSend: autoSend);
          return true;
        }
        // خلاف ذلك: فتح محادثة جديدة (قد يؤدي لتحميل واجهة المحادثة فقط)
        _instance!.sendNewMessage(phone, message, autoSend: autoSend);
        return true;
      } catch (e) {
        debugPrint('⚠️ فشل إرسال رسالة إلى النافذة المفتوحة');
        try {
          _instance!.sendNewMessage(phone, message, autoSend: autoSend);
          return true;
        } catch (_) {}
      }
    }
    return false;
  }

  // ================== حارس الزر (FAB Guard) ==================
  static void _startFabGuard() {
    if (suppressIndividualFabs) return; // FloatingToolbar يتولى المهمة
    if (_fabGuardTimer?.isActive ?? false) return;
    _fabGuardTimer = Timer.periodic(const Duration(seconds: 2), (t) {
      if (suppressIndividualFabs) { t.cancel(); return; }
      // إذا اختفى أو أصبح غير مثبت (unmounted) بسبب إعادة بناء / تسجيل خروج / تبديل نظام
      if ((_fabEntry == null || !_fabEntry!.mounted) && _savedContext != null) {
        debugPrint('🔄 FAB guard: recreating missing/unmounted WhatsApp FAB');
        try {
          if (_savedContext!.mounted) {
            showFloatingButton(_savedContext!);
          }
        } catch (e) {
          debugPrint('⚠️ FAB guard recreate error');
        }
      }
    });
  }

  static void _stopFabGuard() {
    try {
      _fabGuardTimer?.cancel();
    } catch (_) {}
    _fabGuardTimer = null;
  }

  /// تهيئة جذرية لمرة واحدة لتثبيت الـ rootOverlay
  static void ensureGlobal(BuildContext context) {
    if (!_initialized) {
      try {
        _rootOverlay = Overlay.of(context, rootOverlay: true);
        _initialized = _rootOverlay != null;
        debugPrint('✅ WhatsApp global overlay initialized: $_initialized');

        // إظهار زر المحادثات العائم
        if (_initialized && _conversationsFabEntry == null) {
          showConversationsFloatingButton(context, isAdmin: _isAdminUser);
        }
      } catch (e) {
        debugPrint('⚠️ Failed to init global overlay');
      }
    }
  }
}

class WhatsAppBottomWindowContent extends StatefulWidget {
  final String phone;
  final String message;
  final bool autoSend;
  final VoidCallback onClose;
  final VoidCallback onMinimize;

  const WhatsAppBottomWindowContent({
    super.key,
    required this.phone,
    required this.message,
    this.autoSend = false,
    required this.onClose,
    required this.onMinimize,
  });

  @override
  State<WhatsAppBottomWindowContent> createState() =>
      _WhatsAppBottomWindowState();
}

class _WhatsAppBottomWindowState extends State<WhatsAppBottomWindowContent> {
  bool _isLoading = true;
  bool _isLoggedIn = false;
  bool _messageSent = false;
  String? _error;
  WebViewController? _controller;
  wvwin.WebviewController? _winController;
  Timer? _statusMonitor;

  String _currentPhone = '';
  String _currentMessage = '';

  @override
  void initState() {
    super.initState();
    WhatsAppBottomWindow._instance = this;
    _currentPhone = widget.phone;
    _currentMessage = widget.message;

    _checkSavedLoginState();
    _initializeWebView();
  }

  @override
  void dispose() {
    try {
      _statusMonitor?.cancel();
    } catch (e) {
      debugPrint('⚠️ Error canceling status monitor');
    }

    // تنظيف آمن للـ instance reference
    if (WhatsAppBottomWindow._instance == this) {
      WhatsAppBottomWindow._instance = null;
    }

    super.dispose();
  }

  Future<void> _checkSavedLoginState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLogin = prefs.getBool('wa_web_logged_in') ?? false;
      if (savedLogin) {
        debugPrint('✅ جلسة واتساب ويب محفوظة مسبقاً');
        setState(() => _isLoggedIn = true);
      }
    } catch (e) {
      debugPrint('❌ خطأ في فحص حالة تسجيل الدخول');
    }
  }

  Future<void> _initializeWebView() async {
    try {
      if (Platform.isWindows) {
        await _initializeWindowsWebView();
      } else {
        await _initializeFlutterWebView();
      }
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة WebView');
      setState(() {
        _error = 'خطأ في تحميل واتساب';
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeWindowsWebView() async {
    try {
      _winController = wvwin.WebviewController();

      await _winController!.initialize();
      await _winController!.setBackgroundColor(Colors.white);
      await _winController!
          .setPopupWindowPolicy(wvwin.WebviewPopupWindowPolicy.deny);

      _winController!.url.listen((url) {
        debugPrint('🌐 URL تغيّر إلى: $url');
        _handleUrlChange(url);
      });

      _winController!.loadingState.listen((state) {
        if (state == wvwin.LoadingState.navigationCompleted) {
          setState(() => _isLoading = false);
          _startStatusMonitoring();

          // إذا كان الإرسال التلقائي مفعل، نحاول تنفيذه بعد التحميل
          if (widget.autoSend) {
            Timer(const Duration(seconds: 2), () {
              _attemptAutoSendAfterLoad();
            });
          }
        }
      });

      // تحميل واتساب ويب
      final encodedMessage = Uri.encodeComponent(_currentMessage);
      final webUrl =
          'https://web.whatsapp.com/send?phone=$_currentPhone&text=$encodedMessage';
      await _winController!.loadUrl(webUrl);
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة Windows WebView');
      setState(() {
        if (e.toString().toLowerCase().contains('webview2') ||
            e.toString().toLowerCase().contains('edge') ||
            e.toString().toLowerCase().contains('runtime')) {
          _error =
              'يتطلب Microsoft Edge WebView2 Runtime لعمل الواتساب.\n\nيرجى تحميله وتثبيته من موقع مايكروسوفت الرسمي ثم إعادة تشغيل التطبيق.';
        } else {
          _error = 'خطأ في تحميل واتساب ويب';
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeFlutterWebView() async {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            debugPrint('🔄 تقدم التحميل: $progress%');
          },
          onPageStarted: (String url) {
            debugPrint('🌐 بدء تحميل: $url');
            _handleUrlChange(url);
          },
          onPageFinished: (String url) {
            debugPrint('✅ انتهى تحميل: $url');
            setState(() => _isLoading = false);
            _startStatusMonitoring();

            // إذا كان الإرسال التلقائي مفعل، نحاول تنفيذه بعد التحميل
            if (widget.autoSend) {
              Timer(const Duration(seconds: 2), () {
                _attemptAutoSendAfterLoad();
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('❌ خطأ ويب: ${error.description}');
            setState(() {
              _error = 'خطأ في التحميل: ${error.description}';
              _isLoading = false;
            });
          },
        ),
      );

    // تحميل واتساب ويب
    final encodedMessage = Uri.encodeComponent(_currentMessage);
    final webUrl =
        'https://web.whatsapp.com/send?phone=$_currentPhone&text=$encodedMessage';
    await _controller!.loadRequest(Uri.parse(webUrl));
  }

  void _handleUrlChange(String url) {
    if (url.contains('web.whatsapp.com') && !url.contains('/auth')) {
      if (!_isLoggedIn) {
        setState(() => _isLoggedIn = true);
        _saveLoginState();
      }
    }
  }

  Future<void> _saveLoginState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('wa_web_logged_in', true);
      debugPrint('💾 تم حفظ حالة تسجيل الدخول');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ حالة الدخول');
    }
  }

  void _startStatusMonitoring() {
    _statusMonitor?.cancel();
    _statusMonitor = Timer.periodic(const Duration(seconds: 2), (timer) {
      _checkMessageSent();
    });
  }

  Future<void> _checkMessageSent() async {
    try {
      if (Platform.isWindows && _winController != null) {
        try {
          await _winController!.executeScript(
              'document.querySelector("[data-icon=\'msg-check\']") !== null');
          if (!_messageSent) {
            setState(() => _messageSent = true);
            _statusMonitor?.cancel();
            // _showSuccessMessage(); // تم تعطيل إشعار النجاح
          }
        } catch (e) {
          // تجاهل الخطأ واستمر في المحاولة
        }
      } else if (_controller != null) {
        final result = await _controller!.runJavaScriptReturningResult(
            'document.querySelector("[data-icon=\'msg-check\']") !== null');

        if (result.toString() == 'true' && !_messageSent) {
          setState(() => _messageSent = true);
          _statusMonitor?.cancel();
          // _showSuccessMessage(); // تم تعطيل إشعار النجاح
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في فحص حالة الإرسال');
    }
  }

  /// دالة لإرسال رسالة جديدة
  void sendNewMessage(String phone, String message, {bool autoSend = false}) {
    if (!mounted) return;

    debugPrint('📨 إرسال رسالة جديدة: $phone (إرسال تلقائي: $autoSend)');
    // حالة نفس المحادثة: حقن فقط
    if (phone == _currentPhone && _currentPhone.isNotEmpty) {
      debugPrint('♻️ نفس المحادثة الحالية -> حقن رسالة فقط');
      sendAnotherMessageSameChat(message, autoSend: autoSend);
      return;
    }

    // محاولة التحويل السريع أولاً (بدون إعادة تحميل كامل)
    if (_isLoggedIn && !_isLoading) {
      debugPrint('🔄 محاولة التحويل السريع للرقم الجديد...');
      bool quickSwitchSuccess =
          tryQuickSwitchChat(phone, message, autoSend: autoSend);

      if (quickSwitchSuccess) {
        debugPrint('✅ نجح التحويل السريع');
        setState(() {
          _currentPhone = phone;
          _currentMessage = message;
          _messageSent = false;
        });

        // مراقبة حالة الإرسال
        _startStatusMonitoring();
        return;
      }

      debugPrint('⚠️ فشل التحويل السريع، الانتقال لإعادة التحميل الكامل');
    }

    // إذا فشل التحويل السريع أو لم نكن مسجلين دخول، نعيد التحميل الكامل
    debugPrint('🔄 فتح محادثة جديدة برقم مختلف (إعادة تحميل كاملة)');

    setState(() {
      _currentPhone = phone;
      _currentMessage = message;
      _messageSent = false;
      _isLoading = true;
    });

    final encodedMessage = Uri.encodeComponent(message);
    String webUrl =
        'https://web.whatsapp.com/send?phone=$phone&text=$encodedMessage';

    // إذا كان الإرسال التلقائي مفعل، نضيف معامل خاص
    if (autoSend) {
      webUrl += '&auto_send=true';
    }

    if (Platform.isWindows && _winController != null) {
      _winController!.loadUrl(webUrl);
    } else if (!Platform.isWindows && _controller != null) {
      _controller!.loadRequest(Uri.parse(webUrl));
    }

    // إذا كان الإرسال التلقائي مفعل، نحاول تنفيذه بعد التحميل
    if (autoSend) {
      Timer(const Duration(seconds: 3), () {
        _attemptAutoSendAfterLoad();
      });
    }

    _startStatusMonitoring();
  }

  /// محاولة الإرسال التلقائي بعد تحميل الصفحة
  void _attemptAutoSendAfterLoad() {
    if (!mounted || _isLoading) return;

    debugPrint('🤖 محاولة الإرسال التلقائي بعد التحميل');

    final js = """
      (function(){
        try {
          console.log('Attempting auto send after load');
          
          // البحث عن صندوق النص
          const textBoxes = document.querySelectorAll('[contenteditable="true"]');
          if (!textBoxes || textBoxes.length === 0) {
            console.log('No text box found for auto send');
            return false;
          }
          
          const activeBox = textBoxes[textBoxes.length - 1];
          activeBox.focus();
          
          // انتظار قصير ثم بدء عملية TAB
          setTimeout(() => {
            console.log('Starting TAB sequence for auto send');
            // الضغط على TAB 16 مرة للوصول إلى زر الإرسال
            for (let i = 0; i < 16; i++) {
              const tabEvent = new KeyboardEvent('keydown', {
                key: 'Tab', 
                code: 'Tab', 
                which: 9, 
                keyCode: 9, 
                bubbles: true
              });
              document.activeElement.dispatchEvent(tabEvent);
            }
            
            // انتظار قصير ثم الضغط على Enter
            setTimeout(() => {
              console.log('Sending Enter after TAB sequence');
              const enterEvent = new KeyboardEvent('keydown', {
                key: 'Enter', 
                code: 'Enter', 
                which: 13, 
                keyCode: 13, 
                bubbles: true
              });
              document.activeElement.dispatchEvent(enterEvent);
              console.log('Auto send completed after load');
            }, 300);
          }, 500);
          
          return true;
        } catch(e) {
          console.log('Error in auto send after load:', e);
          return false;
        }
      })();
    """;

    try {
      if (Platform.isWindows && _winController != null) {
        _winController!.executeScript(js);
      } else if (_controller != null) {
        _controller!.runJavaScript(js);
      }
    } catch (e) {
      debugPrint('⚠️ فشل في الإرسال التلقائي بعد التحميل');
    }
  }

  /// إرسال رسالة إضافية في نفس المحادثة المفتوحة بدون إعادة تحميل كامل
  void sendAnotherMessageSameChat(String message, {bool autoSend = false}) {
    if (!mounted) return;
    // إن لم نكن في محادثة جاهزة نتراجع إلى sendNewMessage
    if (_currentPhone.isEmpty) {
      debugPrint(
          'ℹ️ لا توجد محادثة حالية، سيتم تجاهل sendAnotherMessageSameChat');
      return;
    }
    _currentMessage = message; // تحديث آخر رسالة (اختياري)
    debugPrint(
        '💬 حقن رسالة جديدة في نفس المحادثة الحالية (إرسال تلقائي: $autoSend)');
    final escaped = message
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r"\n");

    String js;

    if (autoSend) {
      // النسخة التلقائية: لصق النص + TAB×16 + Enter
      js = """
        (function(){
          try {
            const boxes = document.querySelectorAll('[contenteditable="true"]');
            if (!boxes || boxes.length === 0) return false;
            const box = boxes[boxes.length-1];
            box.focus();
            
            // لصق النص
            const dataTransfer = new DataTransfer();
            dataTransfer.setData('text', '$escaped');
            const evt = new ClipboardEvent('paste', { clipboardData: dataTransfer });
            box.dispatchEvent(evt);
            
            // انتظار قصير ثم بدء عملية TAB
            setTimeout(() => {
              // الضغط على TAB 16 مرة للوصول إلى زر الإرسال
              for (let i = 0; i < 16; i++) {
                const tabEvent = new KeyboardEvent('keydown', {
                  key: 'Tab', 
                  code: 'Tab', 
                  which: 9, 
                  keyCode: 9, 
                  bubbles: true
                });
                document.activeElement.dispatchEvent(tabEvent);
              }
              
              // انتظار قصير ثم الضغط على Enter
              setTimeout(() => {
                const enterEvent = new KeyboardEvent('keydown', {
                  key: 'Enter', 
                  code: 'Enter', 
                  which: 13, 
                  keyCode: 13, 
                  bubbles: true
                });
                document.activeElement.dispatchEvent(enterEvent);
              }, 200);
            }, 100);
            
            return true;
          } catch(e){ 
            console.log('خطأ في الإرسال التلقائي:', e);
            return false; 
          }
        })();
      """;
    } else {
      // النسخة العادية: لصق النص + Enter مباشرة
      js = """
        (function(){
          try {
            const boxes = document.querySelectorAll('[contenteditable="true"]');
            if (!boxes || boxes.length === 0) return false;
            const box = boxes[boxes.length-1];
            box.focus();
            const dataTransfer = new DataTransfer();
            dataTransfer.setData('text', '$escaped');
            const evt = new ClipboardEvent('paste', { clipboardData: dataTransfer });
            box.dispatchEvent(evt);
            // محاكاة ضغط Enter
            const enterEvent = new KeyboardEvent('keydown', {key: 'Enter', code: 'Enter', which:13, keyCode:13, bubbles:true});
            box.dispatchEvent(enterEvent);
            return true;
          } catch(e){ return false; }
        })();
      """;
    }

    try {
      if (Platform.isWindows && _winController != null) {
        _winController!.executeScript(js);
      } else if (_controller != null) {
        _controller!.runJavaScript(js);
      }
    } catch (e) {
      debugPrint('⚠️ فشل حقن الرسالة في نفس المحادثة');
    }
  }

  /// محاولة فتح محادثة جديدة (رقم جديد) بدون إعادة تحميل كامل للصفحة
  /// تعود true إذا نجح الحقن، false إذا لم تتوفر البيئة الداخلية (Store) أو فشل التنفيذ
  bool tryQuickSwitchChat(String phone, String message,
      {bool autoSend = false}) {
    if (!mounted) return false;
    // لا نحاول إن لم نكن مسجلين دخول أو الـ WebView ما زال في حالة تحميل
    if (_isLoading) return false;

    // التأكد من أن WhatsApp Store متاح (يتم توفيره بعد اكتمال تهيئة واجهة واتساب)
    final js = _buildQuickSwitchScript(phone, message, autoSend: autoSend);
    try {
      if (Platform.isWindows && _winController != null) {
        _winController!.executeScript(js);
        _currentPhone = phone; // تحديث مبكر لتقليل إعادة التحميل لاحقاً
        return true; // تفادي تحميل كامل
      } else if (!Platform.isWindows && _controller != null) {
        _controller!.runJavaScript(js);
        _currentPhone = phone;
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ فشل quickSwitchChat');
    }
    return false;
  }

  String _buildQuickSwitchScript(String phone, String message,
      {bool autoSend = false}) {
    final escapedMsg = message
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('"', r'\"')
        .replaceAll('\n', r"\n")
        .replaceAll('\r', r"\r");
    final escapedPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');

    // سكريپت محسّن للبحث والتحويل للمحادثة الصحيحة
    return """
      (function(){
        console.log('Starting quick switch for: $escapedPhone (auto send: $autoSend)');
        
        try {
          if (!window.Store || !window.Store.Chat) {
            console.log('Store or Store.Chat not available');
            return false;
          }
          
          const targetPhone = '$escapedPhone@c.us';
          console.log('Searching for: ' + targetPhone);
          
          const existingChat = window.Store.Chat.get(targetPhone);
          if (existingChat) {
            console.log('Found existing chat');
            try {
              window.Store.Cmd.openChatAt(existingChat.id);
              setTimeout(() => injectMessage('$escapedMsg', $autoSend), 500);
              return true;
            } catch(e) {
              console.log('Failed to open existing chat: ' + e);
            }
          }
          
          const allChats = window.Store.Chat.getModelsArray();
          console.log('Searching in ' + allChats.length + ' chats');
          
          const foundChat = allChats.find(chat => {
            if (!chat || !chat.id || !chat.id.user) return false;
            return chat.id.user === '$escapedPhone' || 
                   chat.id._serialized === targetPhone ||
                   (chat.contact && chat.contact.id && chat.contact.id.user === '$escapedPhone');
          });
          
          if (foundChat) {
            console.log('Found chat: ' + foundChat.id._serialized);
            try {
              window.Store.Cmd.openChatAt(foundChat.id);
              setTimeout(() => injectMessage('$escapedMsg', $autoSend), 800);
              return true;
            } catch(e) {
              console.log('Failed to open found chat: ' + e);
            }
          }
          
          console.log('Creating new chat');
          const newChatUrl = 'https://web.whatsapp.com/send?phone=$escapedPhone&text=' + 
                            encodeURIComponent('$escapedMsg');
          
          window.location.href = newChatUrl;
          return true;
          
        } catch(e) { 
          console.log('General error in quick switch: ' + e);
          return false; 
        }
        
        function injectMessage(msg, autoSend) {
          console.log('Starting message injection: ' + msg.substring(0, 50) + '... (auto send: ' + autoSend + ')');
          
          function waitAndInject(attempts = 0) {
            if (attempts > 10) {
              console.log('Max injection attempts reached');
              return false;
            }
            
            console.log('Looking for active chat...');
            
            const activeChat = document.querySelector('[data-testid="conversation-header-contact-name"], .xyorhqc.x1u2wbnr.xds687c');
            if (!activeChat) {
              console.log('No active chat found');
              setTimeout(() => waitAndInject(attempts + 1), 500);
              return;
            }
            
            try {
              const textBoxes = document.querySelectorAll('[contenteditable="true"]');
              if (!textBoxes || textBoxes.length === 0) {
                console.log('No text box found');
                setTimeout(() => waitAndInject(attempts + 1), 300);
                return;
              }
              
              const activeBox = textBoxes[textBoxes.length - 1];
              activeBox.focus();
              
              try {
                const dataTransfer = new DataTransfer();
                dataTransfer.setData('text/plain', msg);
                const pasteEvent = new ClipboardEvent('paste', {
                  clipboardData: dataTransfer,
                  bubbles: true,
                  cancelable: true
                });
                activeBox.dispatchEvent(pasteEvent);
              } catch(e) {
                console.log('First method failed, trying second');
                
                try {
                  activeBox.innerHTML = '';
                  activeBox.textContent = msg;
                  activeBox.dispatchEvent(new InputEvent('input', {
                    data: msg,
                    bubbles: true,
                    cancelable: true
                  }));
                } catch(e2) {
                  console.log('Second method also failed');
                }
              }
              
              setTimeout(() => {
                if (autoSend) {
                  console.log('Auto send enabled - starting TAB sequence');
                  // الضغط على TAB 16 مرة للوصول إلى زر الإرسال
                  for (let i = 0; i < 16; i++) {
                    const tabEvent = new KeyboardEvent('keydown', {
                      key: 'Tab',
                      code: 'Tab',
                      which: 9,
                      keyCode: 9,
                      bubbles: true
                    });
                    document.activeElement.dispatchEvent(tabEvent);
                  }
                  
                  // انتظار قصير ثم الضغط على Enter
                  setTimeout(() => {
                    console.log('Sending Enter after TAB sequence');
                    const enterEvent = new KeyboardEvent('keydown', {
                      key: 'Enter',
                      code: 'Enter',
                      which: 13,
                      keyCode: 13,
                      bubbles: true
                    });
                    document.activeElement.dispatchEvent(enterEvent);
                    console.log('Auto send completed');
                  }, 300);
                } else {
                  // الطريقة العادية
                  const enterEvent = new KeyboardEvent('keydown', {
                    key: 'Enter',
                    code: 'Enter',
                    which: 13,
                    keyCode: 13,
                    bubbles: true
                  });
                  activeBox.dispatchEvent(enterEvent);
                  console.log('Message sent normally');
                }
              }, 300);
              
              return true;
              
            } catch(e) {
              console.log('Error in message injection: ' + e);
              setTimeout(() => waitAndInject(attempts + 1), 300);
              return false;
            }
          }
          
          waitAndInject();
        }
      })();
    """;
  }

  /// فتح صفحة تحميل WebView2 Runtime
  void _launchWebView2Download() async {
    const url =
        'https://developer.microsoft.com/en-us/microsoft-edge/webview2/';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'تعذر فتح رابط التحميل. يرجى البحث عن "Microsoft Edge WebView2 Runtime" وتحميله من موقع مايكروسوفت الرسمي.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في فتح رابط التحميل');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'تعذر فتح رابط التحميل. يرجى البحث عن "Microsoft Edge WebView2 Runtime" وتحميله من موقع مايكروسوفت الرسمي.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// الانتقال لواجهة الواتساب الرئيسية (بدون محادثة محددة)
  void navigateToHome() {
    if (!mounted) return;

    debugPrint('🏠 الانتقال لواجهة الواتساب الرئيسية');

    setState(() {
      _currentPhone = '';
      _currentMessage = '';
      _messageSent = false;
      _isLoading = true;
    });

    const webUrl = 'https://web.whatsapp.com/';

    // تحميل واجهة الواتساب الرئيسية
    if (Platform.isWindows && _winController != null) {
      _winController!.loadUrl(webUrl);
    } else if (!Platform.isWindows && _controller != null) {
      _controller!.loadRequest(Uri.parse(webUrl));
    }

    _startStatusMonitoring();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // شريط العنوان
        Container(
          height: 60,
          decoration: const BoxDecoration(
            color: Color(0xFF25D366),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.chat, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Text(
                'واتساب ويب',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const Spacer(),
              // زر تصغير
              Container(
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon:
                      const Icon(Icons.minimize, color: Colors.white, size: 20),
                  onPressed: () {
                    widget.onMinimize();
                  },
                  tooltip: 'تصغير',
                ),
              ),
              // زر إغلاق
              Container(
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  onPressed: widget.onClose,
                  tooltip: 'إغلاق نهائي',
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        // محتوى الواجهة
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _error = null);
                      _initializeWebView();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                  if (Platform.isWindows && _error!.contains('WebView2')) ...[
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _launchWebView2Download,
                      icon: const Icon(Icons.download),
                      label: const Text('تحميل WebView2'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        // WebView
        if (Platform.isWindows && _winController != null)
          wvwin.Webview(_winController!)
        else if (!Platform.isWindows && _controller != null)
          WebViewWidget(controller: _controller!),

        // مؤشر التحميل
        if (_isLoading)
          Container(
            color: Colors.white.withValues(alpha: 0.9),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF25D366)),
                  SizedBox(height: 16),
                  Text('جاري تحميل واتساب ويب...'),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
